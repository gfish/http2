require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Http2" do
  it "should be able to do normal post-requests." do
    require "json"

    #Test posting keep-alive and advanced post-data.
    Http2.new(:host => "www.partyworm.dk", :debug => false) do |http|
      0.upto(5) do
        resp = http.get("multipart_test.php")

        resp = http.post(:url => "multipart_test.php?choice=post-test", :post => {
          "val1" => "test1",
          "val2" => "test2",
          "val3" => [
            "test3"
          ],
          "val4" => {
            "val5" => "test5"
          },
          "val6" => {
            "val7" => [
              {
                "val8" => "test8"
              }
            ]
          },
          "val9" => ["a", "b", "d"]
        })
        res = JSON.parse(resp.body)

        raise "Expected 'res' to be a hash." if !res.is_a?(Hash)
        raise "Error 1" if res["val1"] != "test1"
        raise "Error 2" if res["val2"] != "test2"
        raise "Error 3" if !res["val3"] or res["val3"][0] != "test3"
        raise "Error 4" if res["val4"]["val5"] != "test5"
        raise "Error 5" if res["val6"]["val7"][0]["val8"] != "test8"
        raise "Array error: '#{res["val9"]}'." if res["val9"][0] != "a" or res["val9"][1] != "b" or res["val9"][2] != "d"
      end
    end
  end

  it "should be able to do multipart-requests and keep-alive when using multipart." do
    Http2.new(:host => "www.partyworm.dk", :follow_redirects => false, :encoding_gzip => false, :debug => false) do |http|
      0.upto(5) do
        fpath = File.realpath(__FILE__)
        fpath2 = "#{File.realpath(File.dirname(__FILE__))}/../lib/http2.rb"

        resp = http.post_multipart(:url => "multipart_test.php", :post => {
          "test_var" => "true",
          "test_file1" => {
            :fpath => fpath,
            :filename => "specfile"
          },
          "test_file2" => {
            :fpath => fpath2,
            :filename => "http2.rb"
          }
        })

        data = JSON.parse(resp.body)

        raise "Expected 'test_var' post to be 'true' but it wasnt: '#{data["post"]["test_var"]}'." if data["post"]["test_var"] != "true"
        raise "Expected 'test_file1' to be the same as file but it wasnt:\n#{data["files_data"]["test_file1"]}\n\n#{File.read(fpath)}" if data["files_data"]["test_file1"] != File.read(fpath)
        raise "Expected 'test_file2' to be the same as file but it wasnt:\n#{data["files_data"]["test_file2"]}\n\n#{File.read(fpath)}" if data["files_data"]["test_file2"] != File.read(fpath2)
      end
    end
  end

  it "it should be able to handle keep-alive correctly" do
    urls = [
      "?show=users_search",
      "?show=users_online",
      "?show=drinksdb",
      "?show=forum&fid=9&tid=1917&page=0"
    ]
    urls = ["robots.txt"]

    Http2.new(:host => "www.partyworm.dk", :debug => false) do |http|
      0.upto(105) do |count|
        url = urls[rand(urls.size)]
        #print "Doing request #{count} of 200 (#{url}).\n"
        res = http.get(url)
        raise "Body was empty." if res.body.to_s.length <= 0
      end
    end
  end

  it "should be able to convert URL's to 'is.gd'-short-urls" do
    isgd = Http2.isgdlink("https://github.com/kaspernj/http2")
    raise "Expected isgd-var to be valid but it wasnt: '#{isgd}'." if !isgd.match(/^http:\/\/is\.gd\/([A-z\d]+)$/)
  end

  it "should raise exception when something is not found" do
    expect{
      Http2.new(:host => "www.partyworm.dk") do |http|
        http.get("something_that_does_not_exist.php")
      end
    }.to raise_error(::Http2::Errors::Notfound)
  end

  it "should be able to post json" do
    Http2.new(:host => "http2test.kaspernj.org") do |http|
      res = http.post(
        :url => "/jsontest.php",
        :json => {:testkey => "testvalue"}
      )

      data = JSON.parse(res.body)
      data["_SERVER"]["CONTENT_TYPE"].should eql("application/json")
      data["PHP_JSON_INPUT"]["testkey"].should eql("testvalue")
    end
  end

  it "should be able to post custom content types" do
    require "json"

    Http2.new(:host => "http2test.kaspernj.org") do |http|
      res = http.post(
        :url => "/content_type_test.php",
        :content_type => "plain/text",
        :post => "test1_test2_test3"
      )

      data = JSON.parse(res.body)
      data["_SERVER"]["CONTENT_TYPE"].should eql("plain/text")
      data["PHP_INPUT"].should eql("test1_test2_test3")
    end
  end
end