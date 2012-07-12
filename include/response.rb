class Http2::Response
  attr_reader :args
  
  def initialize(args = {})
    @args = args
    @args[:headers] = {} if !@args.key?(:headers)
    @args[:body] = "" if !@args.key?(:body)
  end
  
  #Returns headers given from the host for the result.
  #===Examples
  # headers_hash = res.headers
  def headers
    return @args[:headers]
  end
  
  #Returns a certain header by name or false if not found.
  #===Examples
  # val = res.header("content-type")
  def header(key)
    return false if !@args[:headers].key?(key)
    return @args[:headers][key].first.to_s
  end
  
  #Returns true if a header of the given string exists.
  #===Examples
  # print "No content-type was given." if !http.header?("content-type")
  def header?(key)
    return true if @args[:headers].key?(key) and @args[:headers][key].first.to_s.length > 0
    return false
  end
  
  #Returns the code of the result (200, 404, 500 etc).
  #===Examples
  # print "An internal error occurred." if res.code.to_i == 500
  def code
    return @args[:code]
  end
  
  #Returns the HTTP-version of the result.
  #===Examples
  # print "We are using HTTP 1.1 and should support keep-alive." if res.http_version.to_s == "1.1"
  def http_version
    return @args[:http_version]
  end
  
  #Returns the complete body of the result as a string.
  #===Examples
  # print "Looks like we caught the end of it as well?" if res.body.to_s.downcase.index("</html>") != nil
  def body
    return @args[:body]
  end
  
  #Returns the charset of the result.
  def charset
    return @args[:charset]
  end
  
  #Returns the content-type of the result as a string.
  #===Examples
  # print "This body can be printed - its just plain text!" if http.contenttype == "text/plain"
  def contenttype
    return @args[:contenttype]
  end
end