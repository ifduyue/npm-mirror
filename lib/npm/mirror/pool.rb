require 'thread'

module Npm
  module Mirror
    class Pool
      attr_accessor :size

      def initialize(size)
        @size = size
        @queue = Queue.new
        @running = false
      end

      def running?
        @running
      end

      def run
        return if running?
        @running = true
        @threads = Array.new(@size) do |i|
          Thread.new do
            Thread.current[:id] = i
            catch(:exit) do
              loop do
                job, args = @queue.pop
                job.call(*args)
              end
            end
          end
        end
      end

      def run_til_done
        run

        until @queue.empty? && @queue.num_waiting == @size
          @threads.each { |t| t.join 0.2 }
          l = @size.to_s.size
          master = 'Master'.ljust(%w(Thread- Master).map(&:size).max + l)
          puts "[#{master}] Queue size: #{@queue.size}, Waiting thread: " \
               "#{@queue.num_waiting}"
        end

        terminate
      end

      def terminate
        return unless running?

        @running = false
        @size.times do
          enqueue_job { throw :exit }
        end

        @threads.each { |t| t.join 0.2 }
        @threads.each { |t| t.kill }
      end

      def enqueue_job(*args, &block)
        @queue << [block, args]
      end
    end  # class Pool
  end  # Mirror
end  # module Npm
