Dir[File.join(File.dirname(__FILE__), 'rsyslog/*.rb')].sort.each { |lib| require lib }