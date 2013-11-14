#This class tries to emulate a browser in Ruby without any visual stuff. Remember cookies, keep sessions alive, reset connections according to keep-alive rules and more.
#===Examples
# Http2.new(:host => "www.somedomain.com", :port => 80, :ssl => false, :debug => false) do |http|
#  res = http.get("index.rhtml?show=some_page")
#  html = res.body
#  print html
#  
#  res = res.post("index.rhtml?choice=login", {"username" => "John Doe", "password" => 123})
#  print res.body
#  print "#{res.headers}"
# end
class Http2
  #Autoloader for subclasses.
  def self.const_missing(name)
    require "#{File.dirname(__FILE__)}/../include/#{name.to_s.downcase}.rb"
    return Http2.const_get(name)
  end
  
  #Converts a URL to "is.gd"-short-URL.
  def self.isgdlink(url)
    Http2.new(:host => "is.gd") do |http|
      resp = http.get("/api.php?longurl=#{url}")
      return resp.body
    end
  end
  
  attr_reader :cookies, :args, :resp
  
  VALID_ARGUMENTS_INITIALIZE = [:host, :port, :ssl, :nl, :user_agent, :raise_errors, :follow_redirects, :debug, :encoding_gzip, :autostate, :basic_auth, :extra_headers, :proxy]
  def initialize(args = {})
    args = {:host => args} if args.is_a?(String)
    raise "Arguments wasnt a hash." if !args.is_a?(Hash)
    
    args.each do |key, val|
      raise "Invalid key: '#{key}'." if !VALID_ARGUMENTS_INITIALIZE.include?(key)
    end
    
    @args = args
    @cookies = {}
    @debug = @args[:debug]
    @autostate_values = {} if @args[:autostate]
    
    require "monitor" unless ::Kernel.const_defined?(:Monitor)
    @mutex = Monitor.new
    
    if !@args[:port]
      if @args[:ssl]
        @args[:port] = 443
      else
        @args[:port] = 80
      end
    end
    
    if @args[:nl]
      @nl = @args[:nl]
    else
      @nl = "\r\n"
    end
    
    if @args[:user_agent]
      @uagent = @args[:user_agent]
    else
      @uagent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)"
    end
    
    if !@args.key?(:raise_errors) || @args[:raise_errors]
      @raise_errors = true
    else
      @raise_errors = false
    end
    
    raise "No host was given." if !@args[:host]
    self.reconnect
    
    if block_given?
      begin
        yield(self)
      ensure
        self.destroy
      end
    end
  end
  
  #Closes current connection if any, changes the arguments on the object and reconnects keeping all cookies and other stuff intact.
  def change(args)
    self.close
    @args.merge!(args)
    self.reconnect
  end
  
  #Closes the current connection if any.
  def close
    @sock.close if @sock and !@sock.closed?
    @sock_ssl.close if @sock_ssl and !@sock_ssl.closed?
    @sock_plain.close if @sock_plain and !@sock_plain.closed?
  end
  
  #Returns boolean based on the if the object is connected and the socket is working.
  #===Examples
  # puts "Socket is working." if http.socket_working?
  def socket_working?
    return false if !@sock or @sock.closed?
    
    if @keepalive_timeout and @request_last
      between = Time.now.to_i - @request_last.to_i
      if between >= @keepalive_timeout
        puts "Http2: We are over the keepalive-wait - returning false for socket_working?." if @debug
        return false
      end
    end
    
    return true
  end
  
  #Destroys the object unsetting all variables and closing all sockets.
  #===Examples
  # http.destroy
  def destroy
    @args = nil
    @cookies = nil
    @debug = nil
    @mutex = nil
    @uagent = nil
    @keepalive_timeout = nil
    @request_last = nil
    
    @sock.close if @sock and !@sock.closed?
    @sock = nil
    
    @sock_plain.close if @sock_plain and !@sock_plain.closed?
    @sock_plain = nil
    
    @sock_ssl.close if @sock_ssl and !@sock_ssl.closed?
    @sock_ssl = nil
  end
  
  #Reconnects to the host.
  def reconnect
    require "socket"
    puts "Http2: Reconnect." if @debug
    
    #Reset variables.
    @keepalive_max = nil
    @keepalive_timeout = nil
    @connection = nil
    @contenttype = nil
    @charset = nil
    
    #Open connection.
    if @args[:proxy] && @args[:ssl]
      print "Http2: Initializing proxy stuff.\n" if @debug
      @sock_plain = TCPSocket.new(@args[:proxy][:host], @args[:proxy][:port])
      
      @sock_plain.write("CONNECT #{@args[:host]}:#{@args[:port]} HTTP/1.0#{@nl}")
      @sock_plain.write("User-Agent: #{@uagent}#{@nl}")
      
      if @args[:proxy][:user] and @args[:proxy][:passwd]
        credential = ["#{@args[:proxy][:user]}:#{@args[:proxy][:passwd]}"].pack("m")
        credential.delete!("\r\n")
        @sock_plain.write("Proxy-Authorization: Basic #{credential}#{@nl}")
      end
      
      @sock_plain.write(@nl)
      
      res = @sock_plain.gets
      raise res if res.to_s.downcase != "http/1.0 200 connection established#{@nl}"
    elsif @args[:proxy]
      print "Http2: Opening socket connection to '#{@args[:host]}:#{@args[:port]}' through proxy '#{@args[:proxy][:host]}:#{@args[:proxy][:port]}'.\n" if @debug
      @sock_plain = TCPSocket.new(@args[:proxy][:host], @args[:proxy][:port].to_i)
    else
      print "Http2: Opening socket connection to '#{@args[:host]}:#{@args[:port]}'.\n" if @debug
      @sock_plain = TCPSocket.new(@args[:host], @args[:port].to_i)
    end
    
    if @args[:ssl]
      print "Http2: Initializing SSL.\n" if @debug
      require "openssl" unless ::Kernel.const_defined?(:OpenSSL)
      
      ssl_context = OpenSSL::SSL::SSLContext.new
      #ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      
      @sock_ssl = OpenSSL::SSL::SSLSocket.new(@sock_plain, ssl_context)
      @sock_ssl.sync_close = true
      @sock_ssl.connect
      
      @sock = @sock_ssl
    else
      @sock = @sock_plain
    end
  end
  
  #Forces various stuff into arguments-hash like URL from original arguments and enables single-string-shortcuts and more.
  def parse_args(*args)
    if args.length == 1 and args.first.is_a?(String)
      args = {:url => args.first}
    elsif args.length >= 2
      raise "Couldnt parse arguments."
    elsif args.is_a?(Array) and args.length == 1
      args = args.first
    else
      raise "Invalid arguments: '#{args.class.name}'."
    end
    
    if !args.key?(:url) or !args[:url]
      raise "No URL given: '#{args[:url]}'."
    elsif args[:url].to_s.split("\n").length > 1
      raise "Multiple lines given in URL: '#{args[:url]}'."
    end
    
    return args
  end
  
  #Returns a result-object based on the arguments.
  #===Examples
  # res = http.get("somepage.html")
  # print res.body #=> <String>-object containing the HTML gotten.
  def get(args)
    args = self.parse_args(args)
    
    if args.key?(:method) && args[:method]
      method = args[:method].to_s.upcase
    else
      method = "GET"
    end
    
    header_str = "#{method} /#{args[:url]} HTTP/1.1#{@nl}"
    header_str << self.header_str(self.default_headers(args), args)
    header_str << @nl
    
    @mutex.synchronize do
      print "Http2: Writing headers.\n" if @debug
      print "Header str: #{header_str}\n" if @debug
      self.write(header_str)
      
      print "Http2: Reading response.\n" if @debug
      resp = self.read_response(args)
      
      print "Http2: Done with get request.\n" if @debug
      return resp
    end
  end
  
  # Proxies the request to another method but forces the method to be "DELETE".
  def delete(args)
    if args[:json]
      return self.post(args.merge(:method => :delete))
    else
      return self.get(args.merge(:method => :delete))
    end
  end
  
  #Tries to write a string to the socket. If it fails it reconnects and tries again.
  def write(str)
    #Reset variables.
    @length = nil
    @encoding = nil
    self.reconnect if !self.socket_working?
    
    begin
      raise Errno::EPIPE, "The socket is closed." if !@sock or @sock.closed?
      self.sock_write(str)
    rescue Errno::EPIPE #this can also be thrown by puts.
      self.reconnect
      self.sock_write(str)
    end
    
    @request_last = Time.now
  end
  
  #Returns the default headers for a request.
  #===Examples
  # headers_hash = http.default_headers
  # print "#{headers_hash}"
  def default_headers(args = {})
    return args[:default_headers] if args[:default_headers]
    
    headers = {
      "Connection" => "Keep-Alive",
      "User-Agent" => @uagent
    }
    
    #Possible to give custom host-argument.
    _args = args[:host] ? args : @args
    headers["Host"] = _args[:host]
    headers["Host"] += ":#{_args[:port]}" unless _args[:port] && [80,443].include?(_args[:port].to_i)
    
    if !@args.key?(:encoding_gzip) or @args[:encoding_gzip]
      headers["Accept-Encoding"] = "gzip"
    else
      #headers["Accept-Encoding"] = "none"
    end
    
    if @args[:basic_auth]
      require "base64" unless ::Kernel.const_defined?(:Base64)
      headers["Authorization"] = "Basic #{Base64.encode64("#{@args[:basic_auth][:user]}:#{@args[:basic_auth][:passwd]}").strip}"
    end
    
    if @args[:extra_headers]
      headers.merge!(@args[:extra_headers])
    end
    
    if args[:headers]
      headers.merge!(args[:headers])
    end
    
    return headers
  end
  
  #This is used to convert a hash to valid post-data recursivly.
  def self.post_convert_data(pdata, args = nil)
    praw = ""
    
    if pdata.is_a?(Hash)
      pdata.each do |key, val|
        praw << "&" if praw != ""
        
        if args and args[:orig_key]
          key = "#{args[:orig_key]}[#{key}]"
        end
        
        if val.is_a?(Hash) or val.is_a?(Array)
          praw << self.post_convert_data(val, {:orig_key => key})
        else
          praw << "#{Http2::Utils.urlenc(key)}=#{Http2::Utils.urlenc(Http2.post_convert_data(val))}"
        end
      end
    elsif pdata.is_a?(Array)
      count = 0
      pdata.each do |val|
        praw << "&" if praw != ""
        
        if args and args[:orig_key]
          key = "#{args[:orig_key]}[#{count}]"
        else
          key = count
        end
        
        if val.is_a?(Hash) or val.is_a?(Array)
          praw << self.post_convert_data(val, {:orig_key => key})
        else
          praw << "#{Http2::Utils.urlenc(key)}=#{Http2::Utils.urlenc(Http2.post_convert_data(val))}"
        end
        
        count += 1
      end
    else
      return pdata.to_s
    end
    
    return praw
  end
  
  VALID_ARGUMENTS_POST = [:post, :url, :default_headers, :headers, :json, :method, :cookies, :on_content]
  #Posts to a certain page.
  #===Examples
  # res = http.post("login.php", {"username" => "John Doe", "password" => 123)
  def post(args)
    args.each do |key, val|
      raise "Invalid key: '#{key}'." unless VALID_ARGUMENTS_POST.include?(key)
    end
    
    args = self.parse_args(args)
    content_type = "application/x-www-form-urlencoded"
    
    if args.key?(:method) && args[:method]
      method = args[:method].to_s.upcase
    else
      method = "POST"
    end
    
    if args[:json]
      require "json" unless ::Kernel.const_defined?(:JSON)
      praw = args[:json].to_json
      content_type = "application/json"
    elsif args[:post].is_a?(String)
      praw = args[:post]
    else
      phash = args[:post] ? args[:post].clone : {}
      autostate_set_on_post_hash(phash) if @args[:autostate]
      praw = Http2.post_convert_data(phash)
    end
    
    @mutex.synchronize do
      puts "Doing post." if @debug
      
      header_str = "#{method} /#{args[:url]} HTTP/1.1#{@nl}"
      header_str << self.header_str({"Content-Length" => praw.bytesize, "Content-Type" => content_type}.merge(self.default_headers(args)), args)
      header_str << @nl
      header_str << praw
      header_str << @nl
      
      puts "Http2: Header str: #{header_str}" if @debug
      
      self.write(header_str)
      return self.read_response(args)
    end
  end
  
  #Posts to a certain page using the multipart-method.
  #===Examples
  # res = http.post_multipart("upload.php", {"normal_value" => 123, "file" => Tempfile.new(?)})
  def post_multipart(*args)
    args = self.parse_args(*args)
    
    phash = args[:post].clone
    autostate_set_on_post_hash(phash) if @args[:autostate]
    
    #Generate random string.
    boundary = rand(36**50).to_s(36)
    
    #Use tempfile to store contents to avoid eating memory if posting something really big.
    require "tempfile"
    
    Tempfile.open("http2_post_multipart_tmp_#{boundary}") do |praw|
      phash.each do |key, val|
        praw << "--#{boundary}#{@nl}"
        
        if val.class.name.to_s == "Tempfile" and val.respond_to?(:original_filename)
          praw << "Content-Disposition: form-data; name=\"#{key}\"; filename=\"#{val.original_filename}\";#{@nl}"
          praw << "Content-Length: #{val.to_s.bytesize}#{@nl}"
        elsif val.is_a?(Hash) and val[:filename]
          praw << "Content-Disposition: form-data; name=\"#{key}\"; filename=\"#{val[:filename]}\";#{@nl}"
          
          if val[:content]
            praw << "Content-Length: #{val[:content].to_s.bytesize}#{@nl}"
          elsif val[:fpath]
            praw << "Content-Length: #{File.size(val[:fpath])}#{@nl}"
          else
            raise "Could not figure out where to get content from."
          end
        else
          praw << "Content-Disposition: form-data; name=\"#{key}\";#{@nl}"
          praw << "Content-Length: #{val.to_s.bytesize}#{@nl}"
        end
        
        praw << "Content-Type: text/plain#{@nl}"
        praw << @nl
        
        if val.class.name.to_s == "StringIO"
          praw << val.read
        elsif val.is_a?(Hash) and val[:content]
          praw << val[:content].to_s
        elsif val.is_a?(Hash) and val[:fpath]
          File.open(val[:fpath], "r") do |fp|
            begin
              while data = fp.sysread(4096)
                praw << data
              end
            rescue EOFError
              #ignore.
            end
          end
        else
          praw << val.to_s
        end
        
        praw << @nl
      end
      
      praw << "--#{boundary}--"
      
      
      #Generate header-string containing 'praw'-variable.
      header_str = "POST /#{args[:url]} HTTP/1.1#{@nl}"
      header_str << self.header_str(self.default_headers(args).merge(
        "Content-Type" => "multipart/form-data; boundary=#{boundary}",
        "Content-Length" => praw.size
      ), args)
      header_str << @nl
      
      
      #Debug.
      print "Http2: Headerstr: #{header_str}\n" if @debug
      
      
      #Write and return.
      @mutex.synchronize do
        self.write(header_str)
        
        praw.rewind
        praw.lines do |data|
          self.sock_write(data)
        end
        
        return self.read_response(args)
      end
    end
  end
  
  def sock_write(str)
    str = str.to_s
    return nil if str.empty?
    count = @sock.write(str)
    raise "Couldnt write to socket: '#{count}', '#{str}'." if count <= 0
  end
  
  def sock_puts(str)
    self.sock_write("#{str}#{@nl}")
  end
  
  #Returns a header-string which normally would be used for a request in the given state.
  def header_str(headers_hash, args = {})
    if @cookies.length > 0 and (!args.key?(:cookies) or args[:cookies])
      cstr = ""
      
      first = true
      @cookies.each do |cookie_name, cookie_data|
        cstr << "; " if !first
        first = false if first
        
        if cookie_data.is_a?(Hash)
          cstr << "#{Http2::Utils.urlenc(cookie_data["name"])}=#{Http2::Utils.urlenc(cookie_data["value"])}"
        else
          cstr << "#{Http2::Utils.urlenc(cookie_name)}=#{Http2::Utils.urlenc(cookie_data)}"
        end
      end
      
      headers_hash["Cookie"] = cstr
    end
    
    headers_str = ""
    headers_hash.each do |key, val|
      headers_str << "#{key}: #{val}#{@nl}"
    end
    
    return headers_str
  end
  
  def on_content_call(args, str)
    args[:on_content].call(str) if args.key?(:on_content)
  end
  
  #Reads the response after posting headers and data.
  #===Examples
  # res = http.read_response
  def read_response(args = {})
    @mode = "headers"
    @transfer_encoding = nil
    @resp = Http2::Response.new(:request_args => args, :debug => @debug)
    rec_count = 0
    
    loop do
      begin
        if @length and @length > 0 and @mode == "body"
          line = @sock.read(@length)
          raise "Expected to get #{@length} of bytes but got #{line.bytesize}" if @length != line.bytesize
        else
          line = @sock.gets
        end
        
        if line
          rec_count += line.length
        elsif !line and rec_count <= 0
          @sock = nil
          raise Errno::ECONNABORTED, "Server closed the connection before being able to read anything (KeepAliveMax: '#{@keepalive_max}', Connection: '#{@connection}', PID: '#{Process.pid}')."
        end
        
        puts "<#{@mode}>: '#{line}'" if @debug
      rescue Errno::ECONNRESET => e
        if rec_count > 0
          print "Http2: The connection was reset while reading - breaking gently...\n" if @debug
          @sock = nil
          break
        else
          raise Errno::ECONNABORTED, "Server closed the connection before being able to read anything (KeepAliveMax: '#{@keepalive_max}', Connection: '#{@connection}', PID: '#{Process.pid}')."
        end
      end
      
      break if line.to_s == ""
      
      if @mode == "headers" and line == @nl
        puts "Http2: Changing mode to body!" if @debug
        raise "No headers was given at all? Possibly corrupt state after last request?" if @resp.headers.empty?
        break if @length == 0
        @mode = "body"
        self.on_content_call(args, @nl)
        next
      end
      
      if @mode == "headers"
        self.parse_header(line, args)
      elsif @mode == "body"
        stat = self.parse_body(line, args)
        break if stat == "break"
        next if stat == "next"
      end
    end
    
    
    #Release variables.
    resp = @resp
    @resp = nil
    @mode = nil
    
    
    #Check if we should reconnect based on keep-alive-max.
    if @keepalive_max == 1 or @connection == "close"
      @sock.close if !@sock.closed?
      @sock = nil
    end
    
    
    
    # Validate that the response is as it should be.
    puts "Http2: Validating response." if @debug
    resp.validate!
    
    
    #Check if the content is gzip-encoded - if so: decode it!
    if @encoding == "gzip"
      require "zlib"
      require "stringio"
      io = StringIO.new(resp.args[:body])
      gz = Zlib::GzipReader.new(io)
      untrusted_str = gz.read
      
      begin
        valid_string = ic.encode("UTF-8")
      rescue
        valid_string = untrusted_str.force_encoding("UTF-8").encode("UTF-8", :invalid => :replace, :replace => "").encode("UTF-8")
      end
      
      resp.args[:body] = valid_string
    end
    
    
    
    
    raise "No status-code was received from the server. Headers: '#{resp.headers}' Body: '#{resp.args[:body]}'." if !resp.args[:code]
    
    if (resp.args[:code].to_s == "302" || resp.args[:code].to_s == "307") and resp.header?("location") and (!@args.key?(:follow_redirects) or @args[:follow_redirects])
      require "uri"
      uri = URI.parse(resp.header("location"))
      url = uri.path
      url << "?#{uri.query}" if uri.query.to_s.length > 0
      
      args = {:host => uri.host}
      args[:ssl] = true if uri.scheme == "https"
      args[:port] = uri.port if uri.port
      
      puts "Http2: Redirecting from location-header to '#{url}'." if @debug
      
      if !args[:host] or args[:host] == @args[:host]
        return self.get(url)
      else
        http = Http2.new(args)
        return http.get(url)
      end
    elsif @raise_errors && resp.args[:code].to_i == 500
      err = Http2::Errors::Internalserver.new(resp.body)
      err.response = resp
      raise err
    elsif @raise_errors && resp.args[:code].to_i == 403
      err = Http2::Errors::Noaccess.new(resp.body)
      err.response = resp
      raise err
    elsif @raise_errors && resp.args[:code].to_i == 404
      err = Http2::Errors::Notfound.new(resp.body)
      err.response = resp
      raise err
    else
      autostate_register(resp) if @args[:autostate]
      
      return resp
    end
  end
  
  #Parse a header-line and saves it on the object.
  #===Examples
  # http.parse_header("Content-Type: text/html\r\n")
  def parse_header(line, args = {})
    if match = line.match(/^(.+?):\s*(.+)#{@nl}$/)
      key = match[1].to_s.downcase
      
      if key == "set-cookie"
        Http2::Utils.parse_set_cookies(match[2]).each do |cookie_data|
          @cookies[cookie_data["name"]] = cookie_data
        end
      elsif key == "keep-alive"
        if ka_max = match[2].to_s.match(/max=(\d+)/)
          @keepalive_max = ka_max[1].to_i
          print "Http2: Keepalive-max set to: '#{@keepalive_max}'.\n" if @debug
        end
        
        if ka_timeout = match[2].to_s.match(/timeout=(\d+)/)
          @keepalive_timeout = ka_timeout[1].to_i
          print "Http2: Keepalive-timeout set to: '#{@keepalive_timeout}'.\n" if @debug
        end
      elsif key == "connection"
        @connection = match[2].to_s.downcase
      elsif key == "content-encoding"
        @encoding = match[2].to_s.downcase
      elsif key == "content-length"
        @length = match[2].to_i
      elsif key == "content-type"
        ctype = match[2].to_s
        if match_charset = ctype.match(/\s*;\s*charset=(.+)/i)
          @charset = match_charset[1].downcase
          @resp.args[:charset] = @charset
          ctype.gsub!(match_charset[0], "")
        end
        
        @ctype = ctype
        @resp.args[:contenttype] = @ctype
      elsif key == "transfer-encoding"
        @transfer_encoding = match[2].to_s.downcase.strip
      end
      
      puts "Http2: Parsed header: #{match[1]}: #{match[2]}" if @debug
      @resp.headers[key] = [] unless @resp.headers.key?(key)
      @resp.headers[key] << match[2]
      
      if key != "transfer-encoding" and key != "content-length" and key != "connection" and key != "keep-alive"
        self.on_content_call(args, line)
      end
    elsif match = line.match(/^HTTP\/([\d\.]+)\s+(\d+)\s+(.+)$/)
      @resp.args[:code] = match[2]
      @resp.args[:http_version] = match[1]
      
      self.on_content_call(args, line)
    else
      raise "Could not understand header string: '#{line}'.\n\n#{@sock.read(409600)}"
    end
  end
  
  #Parses the body based on given headers and saves it to the result-object.
  # http.parse_body(str)
  def parse_body(line, args)
    if @resp.args[:http_version] = "1.1"
      return "break" if @length == 0
      
      if @transfer_encoding == "chunked"
        len = line.strip.hex
        
        if len > 0
          read = @sock.read(len)
          return "break" if read == "" or read == @nl
          @resp.args[:body] << read
          self.on_content_call(args, read)
        end
        
        nl = @sock.gets
        if len == 0
          if nl == @nl
            return "break"
          else
            raise "Dont know what to do :'-("
          end
        end
        
        raise "Should have read newline but didnt: '#{nl}'." if nl != @nl
      else
        puts "Http2: Adding #{line.to_s.bytesize} to the body." if @debug
        @resp.args[:body] << line.to_s
        self.on_content_call(args, line)
        return "break" if @resp.header?("content-length") && @resp.args[:body].length >= @resp.header("content-length").to_i
      end
    else
      raise "Dont know how to read HTTP version: '#{@resp.args[:http_version]}'."
    end
  end
  
  private
  
  #Registers the states from a result.
  def autostate_register(res)
    puts "Http2: Running autostate-register on result." if @debug
    @autostate_values.clear
    
    res.body.to_s.scan(/<input type="hidden" name="__(EVENTTARGET|EVENTARGUMENT|VIEWSTATE|LASTFOCUS)" id="(.*?)" value="(.*?)" \/>/) do |match|
      name = "__#{match[0]}"
      id = match[1]
      value = match[2]
      
      puts "Http2: Registered autostate-value with name '#{name}' and value '#{value}'." if @debug
      @autostate_values[name] = Http2::Utils.urldec(value)
    end
    
    raise "No states could be found." if @autostate_values.empty?
  end
  
  #Sets the states on the given post-hash.
  def autostate_set_on_post_hash(phash)
    phash.merge!(@autostate_values)
  end
end