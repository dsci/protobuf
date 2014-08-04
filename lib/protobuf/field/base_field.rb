require 'protobuf/wire_type'
require 'protobuf/field/field_array'

module Protobuf
  module Field
    class BaseField

      ##
      # Constants
      #

      PACKED_TYPES = [
        ::Protobuf::WireType::VARINT,
        ::Protobuf::WireType::FIXED32,
        ::Protobuf::WireType::FIXED64
      ].freeze

      ##
      # Attributes
      #

      attr_reader :default, :deprecated, :extension,
                  :getter_method_name, :message_class, :name,
                  :packed, :rule, :setter_method_name,
                  :tag, :type_class

      ##
      # Class Methods
      #

      def self.default
        nil
      end

      ##
      # Constructor
      #

      def initialize(message_class, rule, type_class, name, tag, options)
        @message_class, @rule, @type_class, @name, @tag = \
          message_class, rule, type_class, name, tag

        @getter_method_name = name
        @setter_method_name = "#{name}="
        @default   = options.delete(:default)
        @extension = options.delete(:extension)
        @packed    = repeated? && options.delete(:packed)
        @deprecated = options.delete(:deprecated)

        warn_excess_options(options) unless options.empty?
        validate_packed_field if packed?
        define_accessor
      end

      ##
      # Public Instance Methods
      #

      def acceptable?(value)
        true
      end

      def coerce!(value)
        value
      end

      def enum?
        false
      end

      def message?
        false
      end

      def default_value
        @default_value ||= case
                           when repeated? then ::Protobuf::Field::FieldArray.new(self).freeze
                           when required? then nil
                           when optional? then typed_default_value
                           end
      end

      # Decode +bytes+ and pass to +message_instance+.
      def set(message_instance, bytes)
        if packed?
          array = message_instance.__send__(getter_method_name)
          method = \
            case wire_type
            when ::Protobuf::WireType::FIXED32 then :read_fixed32
            when ::Protobuf::WireType::FIXED64 then :read_fixed64
            when ::Protobuf::WireType::VARINT  then :read_varint
            end
          stream = StringIO.new(bytes)

          until stream.eof?
            array << decode(::Protobuf::Decoder.__send__(method, stream))
          end
        else
          value = decode(bytes)
          if repeated?
            message_instance.__send__(getter_method_name) << value
          else
            message_instance.__send__(setter_method_name, value)
          end
        end
      end

      # Decode +bytes+ and return a field value.
      def decode(bytes)
        raise NotImplementedError, "#{self.class.name}\#decode"
      end

      # Encode +value+ and return a byte string.
      def encode(value)
        raise NotImplementedError, "#{self.class.name}\#encode"
      end

      def extension?
        !! extension
      end

      # Is this a repeated field?
      def repeated?
        rule == :repeated
      end

      # Is this a repeated message field?
      def repeated_message?
        repeated? && message?
      end

      # Is this a required field?
      def required?
        rule == :required
      end

      # Is this an optional field?
      def optional?
        rule == :optional
      end

      # Is this a deprecated field?
      def deprecated?
        !! deprecated
      end

      # Is this a packed repeated field?
      def packed?
        !! packed
      end

      def to_s
        "#{rule} #{type_class} #{name} = #{tag} #{default ? "[default=#{default.inspect}]" : ''}"
      end

      def type
        $stderr.puts("[DEPRECATED] #{self.class.name}#type usage is deprecated.\nPlease use #type_class instead.")
        type_class
      end

      def warn_if_deprecated
        if ::Protobuf.print_deprecation_warnings? && deprecated?
          $stderr.puts("[WARNING] #{message_class.name}##{name} field usage is deprecated.")
        end
      end

      private

      ##
      # Private Instance Methods
      #

      def define_accessor
        if repeated?
          define_array_getter
          define_array_setter
        else
          define_getter
          define_setter
        end
      end

      def define_array_getter
        field = self
        message_class.class_eval do
          define_method(field.getter_method_name) do
            field.warn_if_deprecated
            @values[field.name] ||= ::Protobuf::Field::FieldArray.new(field)
          end
        end
      end

      def define_array_setter
        field = self
        message_class.class_eval do
          define_method(field.setter_method_name) do |val|
            field.warn_if_deprecated

            if val.is_a?(Array)
              val = val.dup
              val.compact!
            else
              raise TypeError, <<-TYPE_ERROR
                Expected repeated value of type '#{field.type_class}'
                Got '#{val.class}' for repeated protobuf field #{field.name}
              TYPE_ERROR
            end

            if val.nil? || (val.respond_to?(:empty?) && val.empty?)
              @values.delete(field.name)
            else
              @values[field.name] ||= ::Protobuf::Field::FieldArray.new(field)
              @values[field.name].replace(val)
            end
          end
        end
      end

      def define_getter
        field = self
        message_class.class_eval do
          define_method(field.getter_method_name) do
            field.warn_if_deprecated
            @values.fetch(field.name, field.default_value)
          end
        end
      end

      def define_setter
        field = self
        message_class.class_eval do
          define_method(field.setter_method_name) do |val|
            field.warn_if_deprecated

            if val.nil? || (val.respond_to?(:empty?) && val.empty?)
              @values.delete(field.name)
            elsif field.acceptable?(val)
              @values[field.name] = field.coerce!(val)
            else
              raise TypeError, "Unacceptable value #{val} for field #{field.name} of type #{field.type_class}"
            end
          end
        end
      end

      def typed_default_value
        if default.nil?
          self.class.default
        else
          default
        end
      end

      def validate_packed_field
        if packed? && ! ::Protobuf::Field::BaseField::PACKED_TYPES.include?(wire_type)
          raise "Can't use packed encoding for '#{type_class}' type"
        end
      end

      def warn_excess_options(options)
        warn "WARNING: Invalid options: #{options.inspect} (in #{message_class.name}##{name})"
      end

    end
  end
end

