Dir[File.join(File.dirname(__FILE__), 'postfix/*.rb')].sort.each { |lib| require lib }
roles[:postfix] #empty role