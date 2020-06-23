module MicroCisc
  module Vm
    class EmptyDevice < Device
      def initialize
        super(0, 0, 0)
      end
    end
  end
end
