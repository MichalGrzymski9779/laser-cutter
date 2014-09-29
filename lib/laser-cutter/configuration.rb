require 'hashie/mash'
require 'prawn/measurement_extensions'
require 'pdf/core/page_geometry'

module Laser
  module Cutter
    class MissingOption < RuntimeError
    end
    class ZeroValueNotAllowed < MissingOption
    end
    class Configuration < Hashie::Mash
      DEFAULTS = {
          units: 'mm',
          page_size: 'LETTER',
          page_layout: 'portrait',
          metadata: true
      }

      UNIT_SPECIFIC_DEFAULTS = {
          'mm' => {
              margin: 5,
              padding: 5,
              stroke: 0.0254,
          },
          'in' => {
              margin: 0.125,
              padding: 0.1,
              stroke: 0.001,
          }
      }


      SIZE_REGEXP = /[\d\.]+x[\d\.]+x[\d\.]+\/[\d\.]+\/[\d\.]+/

      FLOATS = %w(width height depth thickness notch margin padding stroke)
      NON_ZERO = %w(width height depth thickness stroke)
      REQUIRED = %w(width height depth thickness notch file)

      def initialize(options = {})
        options.delete_if { |k, v| v.nil? }
        if options['units'] && !UNIT_SPECIFIC_DEFAULTS.keys.include?(options['units'])
          options.delete('units')
        end
        self.merge!(DEFAULTS)
        self.merge!(options)
        if self['size'] && self['size'] =~ SIZE_REGEXP
          dim, self['thickness'], self['notch'] = self['size'].split('/')
          self['width'], self['height'], self['depth'] = dim.split('x')
          delete('size')
        end
        FLOATS.each do |k|
          self[k] = self[k].to_f if (self[k] && self[k].is_a?(String))
        end
        self.merge!(UNIT_SPECIFIC_DEFAULTS[self['units']].merge(self))
      end

      def validate!
        missing = []
        REQUIRED.each { |k| missing << k if self[k].nil? }
        raise MissingOption.new("#{missing.join(', ')} #{missing.size > 1 ? 'are' : 'is'} required, but missing.") unless missing.empty?

        zeros = []
        NON_ZERO.each { |k| zeros << k if self[k] == 0 }
        raise ZeroValueNotAllowed.new("#{zeros.join(', ')} #{zeros.size > 1 ? 'are' : 'is'} required, but is zero.") unless zeros.empty?
      end

      def page_size_values
        h = PDF::Core::PageGeometry::SIZES
        array = []
        h.keys.sort.each do |k|
          array << [k, value_from_units(h[k][0].to_f), value_from_units(h[k][1].to_f)]
        end
        array
      end

      # if from_units is nil, we expect it to be in dots per inch (default
      # measurements for Prawn
      def value_from_units value, from_units = nil
        multiplier = if from_units.nil?
                       if units.eql?('in')
                         1.0 / 72.0 # PDF units per inch
                       else
                         25.4 * 1.0 / 72.0
                       end
                     elsif self.units.eql?(from_units)
                       1.0
                     elsif self.units.eql?('in') && from_units.eql?('mm')
                       (1.0 / 25.4)
                     else
                       25.4
                     end
        value.to_f * multiplier
      end

      def all_page_sizes
        output = ""
        page_size_values.each do |k|
          output << sprintf("\t%10s:\t%6.1f x %6.1f\n", *k)
        end
        output
      end

      def change_units(new_units)
        return if (self.units.eql?(new_units) || !UNIT_SPECIFIC_DEFAULTS.keys.include?(new_units))
        k = (self.units == 'in') ? 25.4 : 0.039370079
        FLOATS.each do |field|
          self.send("#{field}=".to_sym, (self.send(field.to_sym) * k).round(5))
        end
        self.units = new_units
      end
    end
  end
end
