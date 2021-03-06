class Http2::Cookie
  attr_reader :name, :value, :path, :expires_raw

  def initialize(args)
    @name = args[:name]
    @value = args[:value]
    @path = args[:path]
    @expires_raw = args[:expires]
  end

  def inspect
    "#<Http2::Cookie name=#{@name} value=#{@value} path=#{@path}>"
  end

  def to_s
    inspect
  end

  def expires
    @expires ||= Time.parse(@expires_raw) if @expires_raw
  end
end
