Dir[File.join(File.dirname(__FILE__), 'redis/*.rb')].sort.each { |lib| require lib }
roles[:redis] #make an empty role