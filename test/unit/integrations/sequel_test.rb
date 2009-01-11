require File.expand_path(File.dirname(__FILE__) + '/../../test_helper')

begin
  # Load library
  require 'rubygems'
  require 'sequel'
  require 'logger'
  
  # Establish database connection
  DB = Sequel.connect('sqlite:///', :loggers => [Logger.new("#{File.dirname(__FILE__)}/../../sequel.log")])
  
  module SequelTest
    class BaseTestCase < Test::Unit::TestCase
      def default_test
      end
      
      protected
        # Creates a new Sequel model (and the associated table)
        def new_model(auto_migrate = true, &block)
          DB.create_table! :foo do
            primary_key :id
            column :state, :string
          end if auto_migrate
          model = Class.new(Sequel::Model(:foo)) do
            def self.name; 'SequelTest::Foo'; end
          end
          model.class_eval(&block) if block_given?
          model
        end
    end
    
    class IntegrationTest < BaseTestCase
      def test_should_match_if_class_inherits_from_sequel
        assert StateMachine::Integrations::Sequel.matches?(new_model)
      end
      
      def test_should_not_match_if_class_does_not_inherit_from_sequel
        assert !StateMachine::Integrations::Sequel.matches?(Class.new)
      end
    end
    
    class MachineByDefaultTest < BaseTestCase
      def setup
        @model = new_model
        @machine = StateMachine::Machine.new(@model)
      end
      
      def test_should_use_save_as_action
        assert_equal :save, @machine.action
      end
    end
    
    class MachineTest < BaseTestCase
      def setup
        @model = new_model
        @machine = StateMachine::Machine.new(@model)
        @machine.state :parked, :idling, :first_gear
      end
      
      def test_should_create_singular_with_scope
        assert @model.respond_to?(:with_state)
      end
      
      def test_should_only_include_records_with_state_in_singular_with_scope
        parked = @model.create :state => 'parked'
        idling = @model.create :state => 'idling'
        
        assert_equal [parked], @model.with_state(:parked).all
      end
      
      def test_should_create_plural_with_scope
        assert @model.respond_to?(:with_states)
      end
      
      def test_should_only_include_records_with_states_in_plural_with_scope
        parked = @model.create :state => 'parked'
        idling = @model.create :state => 'idling'
        
        assert_equal [parked, idling], @model.with_states(:parked, :idling).all
      end
      
      def test_should_create_singular_without_scope
        assert @model.respond_to?(:without_state)
      end
      
      def test_should_only_include_records_without_state_in_singular_without_scope
        parked = @model.create :state => 'parked'
        idling = @model.create :state => 'idling'
        
        assert_equal [parked], @model.without_state(:idling).all
      end
      
      def test_should_create_plural_without_scope
        assert @model.respond_to?(:without_states)
      end
      
      def test_should_only_include_records_without_states_in_plural_without_scope
        parked = @model.create :state => 'parked'
        idling = @model.create :state => 'idling'
        first_gear = @model.create :state => 'first_gear'
        
        assert_equal [parked, idling], @model.without_states(:first_gear).all
      end
      
      def test_should_rollback_transaction_if_false
        @machine.within_transaction(@model.new) do
          @model.create
          false
        end
        
        assert_equal 0, @model.count
      end
      
      def test_should_not_rollback_transaction_if_true
        @machine.within_transaction(@model.new) do
          @model.create
          true
        end
        
        assert_equal 1, @model.count
      end
      
      def test_should_not_override_the_column_reader
        record = @model.new
        record[:state] = 'parked'
        assert_equal 'parked', record.state
      end
      
      def test_should_not_override_the_column_writer
        record = @model.new
        record.state = 'parked'
        assert_equal 'parked', record[:state]
      end
    end
    
    class MachineUnmigratedTest < BaseTestCase
      def setup
        @model = new_model(false)
      end
      
      def test_should_allow_machine_creation
        assert_nothing_raised { StateMachine::Machine.new(@model) }
      end
    end
    
    class MachineWithInitialStateTest < BaseTestCase
      def setup
        @model = new_model
        @machine = StateMachine::Machine.new(@model, :initial => 'parked')
        @record = @model.new
      end
      
      def test_should_set_initial_state_on_created_object
        assert_equal 'parked', @record.state
      end
    end
    
    class MachineWithNonColumnStateAttributeTest < BaseTestCase
      def setup
        @model = new_model
        @machine = StateMachine::Machine.new(@model, :status, :initial => 'parked')
        @record = @model.new
      end
      
      def test_should_define_a_reader_attribute_for_the_attribute
        assert @record.respond_to?(:status)
      end
      
      def test_should_define_a_writer_attribute_for_the_attribute
        assert @record.respond_to?(:status=)
      end
      
      def test_should_set_initial_state_on_created_object
        assert_equal 'parked', @record.status
      end
    end
    
    class MachineWithCallbacksTest < BaseTestCase
      def setup
        @model = new_model
        @machine = StateMachine::Machine.new(@model)
        @machine.state :parked, :idling
        @record = @model.new(:state => 'parked')
        @transition = StateMachine::Transition.new(@record, @machine, :ignite, :parked, :idling)
      end
      
      def test_should_run_before_callbacks
        called = false
        @machine.before_transition(lambda {called = true})
        
        @transition.perform
        assert called
      end
      
      def test_should_pass_transition_into_before_callbacks_with_one_argument
        transition = nil
        @machine.before_transition(lambda {|arg| transition = arg})
        
        @transition.perform
        assert_equal @transition, transition
      end
      
      def test_should_pass_transition_into_before_callbacks_with_multiple_arguments
        callback_args = nil
        @machine.before_transition(lambda {|*args| callback_args = args})
        
        @transition.perform
        assert_equal [@transition], callback_args
      end
      
      def test_should_run_before_callbacks_within_the_context_of_the_record
        context = nil
        @machine.before_transition(lambda {context = self})
        
        @transition.perform
        assert_equal @record, context
      end
      
      def test_should_run_after_callbacks
        called = false
        @machine.after_transition(lambda {called = true})
        
        @transition.perform
        assert called
      end
      
      def test_should_pass_transition_and_result_into_after_callbacks_with_multiple_arguments
        callback_args = nil
        @machine.after_transition(lambda {|*args| callback_args = args})
        
        @transition.perform
        assert_equal [@transition, @record], callback_args
      end
      
      def test_should_run_after_callbacks_with_the_context_of_the_record
        context = nil
        @machine.after_transition(lambda {context = self})
        
        @transition.perform
        assert_equal @record, context
      end
      
      def test_should_allow_symbolic_callbacks
        callback_args = nil
        
        klass = class << @record; self; end
        klass.send(:define_method, :after_ignite) do |*args|
          callback_args = args
        end
        
        @machine.before_transition(:after_ignite)
        
        @transition.perform
        assert_equal [@transition], callback_args
      end
      
      def test_should_allow_string_callbacks
        class << @record
          attr_reader :callback_result
        end
        
        @machine.before_transition('@callback_result = [1, 2, 3]')
        @transition.perform
        
        assert_equal [1, 2, 3], @record.callback_result
      end
    end
  end
rescue LoadError
  $stderr.puts 'Skipping Sequel tests. `gem install sequel` and try again.'
end