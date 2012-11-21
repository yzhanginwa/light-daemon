module LightDaemon
  class Daemon
    DEFAULT_PID_FILE = "/tmp/light_daemon.pid"

    class << self
      def start(obj, options={})
        @options = self.make_options(options)
        @pid_file = @options[:pid_file]
        if self.get_pid
          raise "The pid file \"#{@pid_file}\" existed already. You need to stop the daemon first."
        end
        self.new(obj, @options).start
      end
  
      def stop(pid_file=DEFAULT_PID_FILE)
        @pid_file = pid_file
        if(pid = self.get_pid)
          begin
            Process.kill("TERM", pid)
          rescue Errno::ESRCH   
            # no such process. do nothing
          end
          self.clear_pid
        end
      end

      def get_pid
        return nil unless File.exist?(@pid_file)
        begin 
          File.open(@pid_file) {|f| f.read}.to_i
        rescue
          nil
        end
      end

      def set_pid(pid)
        File.open(@pid_file, 'w') {|f| f.write(pid.to_s)}
      end

      def clear_pid
        File.unlink(@pid_file)
      end

      def make_options(options)
        options[:children] ||= 1
        options[:monitor_cycle] ||= 10    # seconds
        options[:pid_file] ||= DEFAULT_PID_FILE
        options
      end

      # for debugging 
#      def log(msg)
#        File.open("/tmp/yi.txt", "a") do |f|
#          f.puts msg
#        end
#      end
    end

    def initialize(obj, options)
      daemonize
      self.class.set_pid(Process.pid)

      @options = options
      @obj = obj
      @processes = [] 
      @is_child = false
      signal_handling
    end

    def signal_handling
      $keep_running = true
      Signal.trap "TERM" do
        unless @is_child
          @processes.each do |pid|
            Process.kill("TERM", pid)
          end

          sleep(3)
          options[:children].times do 
            @processes.size.times do
              pid = @processes.shift
              if process_alive?(pid)
                @processes << pid
                sleep(3)
              end
            end  
          end
          @processes.each do |pid|
            Process.kill(9, pid)
          end
        end
        $keep_running = false
      end
    end


    def process_alive?(pid)
      return false unless pid
      begin
        Process.kill(0, pid)
        return true
      rescue Errno::ESRCH
        return false
      rescue ::Exception   # for example on EPERM (process exists but does not belong to us)
        return true
      end
    end

    def start
      @options[:children].times do 
        if pid = fork 
          @processes << pid
          Process.detach(pid)
        else
          run_child
          return
        end
      end

      while($keep_running)
        sleep(@options[:monitor_cycle])

        @processes.each_with_index do |pid, index|
          unless process_alive?(pid)
            if pid = fork
              @processes[index] = pid
              Process.detach(pid)
              sleep(2)
            else 
              run_child
              return
            end  
          else
          end
          sleep(1)
        end
      end
      self.class.clear_pid(@options[:pid_file])
    end

    # some code in this method is learned from gem daemons
    def daemonize
      fork && exit
      unless Process.setsid
        raise 'cannot detach from controlling terminal'
      end

      trap 'SIGHUP', 'IGNORE'
      exit if fork

      begin; STDIN.reopen "/dev/null"; rescue ::Exception; end
      begin; STDOUT.reopen "/dev/null"; rescue ::Exception; end
      begin; STDERR.reopen STDOUT; rescue ::Exception; end
      STDERR.sync = true
    end

    def run_child
      @is_child = true
      target_obj = (@obj.class.name == 'String')? Object.const_get(@obj).new : @obj
      while($keep_running)
        break unless target_obj.send(:call)
      end
    end
  end
end
