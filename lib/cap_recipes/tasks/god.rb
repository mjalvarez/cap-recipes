Dir[File.join(File.dirname(__FILE__), 'god/*.rb')].sort.each { |lib| require lib }