require 'json'
require 'test_helper'

class ExperimentTest < MiniTest::Unit::TestCase

  def test_no_qualifier
    e = Experiments::Experiment.new('test')
    assert !e.has_qualifier?
    assert e.everybody_qualifies?
  end

  def test_qualifier
    e = Experiments::Experiment.new('test') do |experiment|
      qualify { |subject| subject.country == 'CA' }
      groups do
        group :all, 100
      end
    end

    assert e.has_qualifier?
    assert !e.everybody_qualifies?

    subject_stub = Struct.new(:id, :country)
    ca_subject = subject_stub.new(1, 'CA')
    us_subject = subject_stub.new(1, 'US')

    assert e.qualifier.call(ca_subject)
    assert !e.qualifier.call(us_subject)

    qualified = e.assign(ca_subject)
    assert_kind_of Experiments::Assignment, qualified
    assert_equal e.group(:all), qualified.group

    non_qualified = e.assign(us_subject)
    assert_kind_of Experiments::Assignment, non_qualified
    assert !non_qualified.qualified?
    assert_equal nil, non_qualified.group
  end

  def test_assignment
    e = Experiments::Experiment.new('test') do
      qualify { |subject| subject <= 2 }
      groups do
        group :a, :half
        group :b, :rest
      end
    end

    assignment = e.assign(1)
    assert_kind_of Experiments::Assignment, assignment
    assert assignment.qualified?
    assert !assignment.returning?
    assert_equal assignment.group, e.group(:a)

    assignment = e.assign(3)
    assert_kind_of Experiments::Assignment, assignment
    assert !assignment.qualified?

    assert_equal :a,  e.switch(1)
    assert_equal :b,  e.switch(2)
    assert_equal nil, e.switch(3)
  end

  def test_subject_identifier
    e = Experiments::Experiment.new('test')
    assert_equal '123', e.retrieve_subject_identifier(stub(id: 123, to_s: '456'))
    assert_equal '456', e.retrieve_subject_identifier(stub(to_s: '456'))
    assert_raises(Experiments::EmptySubjectIdentifier) { e.retrieve_subject_identifier(stub(id: nil)) }
    assert_raises(Experiments::EmptySubjectIdentifier) { e.retrieve_subject_identifier(stub(to_s: '')) }
  end

  def test_new_unqualified_assignment_without_store_unqualified
    mock_store, mock_qualifier = Experiments::Storage::MockStorage.new, mock('qualifier')
    e = Experiments::Experiment.new('test') do
      qualify { mock_qualifier.qualifies? }
      storage mock_store, store_unqualified: false
    end

    mock_qualifier.expects(:qualifies?).returns(false)
    mock_store.expects(:retrieve_assignment).never
    mock_store.expects(:store_assignment).never
    e.assign(mock('subject'))
  end

  def test_returning_qualified_assignment_without_store_unqualified
    mock_store, mock_qualifier = Experiments::Storage::MockStorage.new, mock('qualifier')
    e = Experiments::Experiment.new('test') do
      qualify { mock_qualifier.qualifies? }
      storage mock_store, store_unqualified: false
      groups { group :all, 100 }
    end

    qualified_assignment = e.subject_assignment(mock('identifier'), e.group(:all), Time.now)
    mock_qualifier.expects(:qualifies?).returns(true)
    mock_store.expects(:retrieve_assignment).returns(qualified_assignment).once
    mock_store.expects(:store_assignment).never
    e.assign(mock('subject'))
  end    

  def test_new_unqualified_assignment_with_store_unqualified
    mock_store, mock_qualifier = Experiments::Storage::MockStorage.new, mock('qualifier')
    e = Experiments::Experiment.new('test') do
      qualify { mock_qualifier.qualifies? }
      storage mock_store, store_unqualified: true
    end

    mock_qualifier.expects(:qualifies?).returns(false)
    mock_store.expects(:retrieve_assignment).returns(nil).once
    mock_store.expects(:store_assignment).once
    e.assign(mock('subject'))
  end

  def test_returning_unqualified_assignment_with_store_unqualified
    mock_store, mock_qualifier = Experiments::Storage::MockStorage.new, mock('qualifier')
    e = Experiments::Experiment.new('test') do
      qualify { mock_qualifier.qualifies? }
      storage mock_store, store_unqualified: true
    end

    unqualified_assignment = e.subject_assignment(mock('subject_identifier'), nil, Time.now)
    mock_qualifier.expects(:qualifies?).never
    mock_store.expects(:retrieve_assignment).returns(unqualified_assignment).once
    mock_store.expects(:store_assignment).never
    e.assign(mock('subject'))
  end

  def test_returning_qualified_assignment_with_store_unqualified
    mock_store, mock_qualifier = Experiments::Storage::MockStorage.new, mock('qualifier')
    e = Experiments::Experiment.new('test') do
      qualify { mock_qualifier.qualifies? }
      storage mock_store, store_unqualified: true
      groups { group :all, 100 }
    end

    qualified_assignment = e.subject_assignment(mock('subject_identifier'), e.group(:all), Time.now)
    mock_qualifier.expects(:qualifies?).never
    mock_store.expects(:retrieve_assignment).returns(qualified_assignment).once
    mock_store.expects(:store_assignment).never
    e.assign(mock('subject'))
  end

  def test_disqualify
    e = Experiments::Experiment.new('test') do
      groups { group :all, 100 }
    end

    subject = stub(id: 'walrus')
    original_assignment = e.assign(subject)
    assert original_assignment.qualified?
    new_assignment = e.disqualify(subject)
    assert !new_assignment.qualified?
  end

  def test_assignment_event_logging
    e = Experiments::Experiment.new('test') do
      groups { group :all, 100 }
    end

    e.stubs(:event_logger).returns(logger = mock('event_logger'))
    logger.expects(:log_assignment).with(kind_of(Experiments::Assignment))

    e.assign(stub(id: 'subject_identifier'))
  end

  def test_conversion_event_logging
    e = Experiments::Experiment.new('test')

    e.stubs(:event_logger).returns(logger = mock('logger'))
    logger.expects(:log_conversion).with(kind_of(Experiments::Conversion))

    conversion = e.convert(subject = stub(id: 'test_subject'), :my_goal)
    assert_equal 'test_subject', conversion.subject_identifier
    assert_equal :my_goal, conversion.goal 
  end

  def test_json
    e = Experiments::Experiment.new(:json) do
      name 'testing'
      subject_type 'visitor'
      groups do
        group :a, :half
        group :b, :rest
      end
    end

    json = JSON.parse(e.to_json)
    assert_equal 'json', json['handle']
    assert_equal false, json['has_qualifier']
    assert_kind_of Enumerable, json['groups']
    assert_equal 'testing', json['metadata']['name']
    assert_equal 'visitor', json['subject_type']
  end

  def test_storage_read_failure
    storage_mock = Experiments::Storage::MockStorage.new
    e = Experiments::Experiment.new(:json) do
      groups { group :all, 100 }
      storage storage_mock
    end

    storage_mock.stubs(:retrieve_assignment).raises(Experiments::StorageError, 'storage read issues')
    rescued_assignment = e.assign(stub(id: 123))
    assert !rescued_assignment.qualified?
  end

  def test_storage_write_failure
    storage_mock = Experiments::Storage::MockStorage.new
    e = Experiments::Experiment.new(:json) do
      groups { group :all, 100 }
      storage storage_mock
    end

    storage_mock.expects(:retrieve_assignment).returns(e.subject_assignment(mock('subject_identifier'), e.group(:all)))
    storage_mock.expects(:store_assignment).raises(Experiments::StorageError, 'storage write issues')
    rescued_assignment = e.assign(stub(id: 456))
    assert !rescued_assignment.qualified?
  end

  def test_initial_started_at
    e = Experiments::Experiment.new('test') do
      groups { group :all, 100 }
    end

    e.subject_storage.expects(:retrieve_start_timestamp).returns(nil)
    e.subject_storage.expects(:store_start_timestamp).once
    e.send(:ensure_experiment_has_started)
  end

  def test_subsequent_started_at_when_start_time_is_memoized
    e = Experiments::Experiment.new('test') do
      groups { group :all, 100 }
    end

    e.send(:ensure_experiment_has_started)
    e.subject_storage.expects(:retrieve_start_timestamp).never
    e.subject_storage.expects(:store_start_timestamp).never
    e.send(:ensure_experiment_has_started)
  end

  def test_subsequent_started_at_when_start_time_is_not_memoized
    e = Experiments::Experiment.new('test') do
      groups { group :all, 100 }
    end

    e.subject_storage.expects(:retrieve_start_timestamp).returns(Time.now.utc)
    e.subject_storage.expects(:store_start_timestamp).never
    e.send(:ensure_experiment_has_started)
  end

  def test_qualify_based_on_experiment_start_timestamp
    Time.stubs(:now).returns(Time.parse('2012-01-01T00:00:00Z'))
    e = Experiments::Experiment.new('test') do
      qualify { |subject| subject.created_at >= self.started_at }
      groups { group :all, 100 }
    end

    subject = stub(id: 'old', created_at: Time.parse('2011-01-01T00:00:00Z'))
    assert !e.assign(subject).qualified?

    subject = stub(id: 'new', created_at: Time.parse('2013-01-01T00:00:00Z'))
    assert e.assign(subject).qualified?
  end

  def test_experiment_starting_behavior
    e = Experiments::Experiment.new('starting_test') do
      groups { group :all, 100 }
    end

    assert !e.started?, "The experiment should not have started yet"

    e.assign(stub(id: '123'))
    assert e.started?, "The experiment should have started after the first assignment"
  end
end
