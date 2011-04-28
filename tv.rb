require "getoptlong"
require "date"
require "net/http"
require "cgi"
require 'rexml/document'
require 'pathname'
require 'find'
require 'forwardable'
include REXML

API_KEY = 'xxx'

class Series
  
  def find(name)
		url = URI.parse('http://thetvdb.com')
		res = Net::HTTP.start(url.host, url.port) do |http|
			http.get('/api/GetSeries.php?seriesname=' +   CGI::escape(name))
		end
		doc = Document.new res.body
		
		result = []		
		doc.elements.each("Data/Series") do |element|
		  s = Hash.new

	    s[:name] = element.elements["SeriesName"].text if not element.elements["SeriesName"].nil?
      s[:firstaired] = element.elements["FirstAired"].text if not element.elements["FirstAired"].nil?
      s[:banner] = element.elements["banner"].text if not element.elements["banner"].nil?
      s[:overview] = element.elements["Overview"].text if not element.elements["Overview"].nil?
      s[:id] = element.elements["seriesid"].text if not element.elements["seriesid"].nil?
		  result << s
		end
		return result
	end
	
end

class Season
  attr_reader :number
  attr_reader :episodes
  
  def initialize(serie, number)
    @number = number
    @episodes = []
  end
  
  def add(episode)
    episode.season = self
    @episodes << episode
  end
  
  def each
    0.upto(@episodes.length - 1) do |x|
      yield @episodes[x]
    end
  end
  
  def count
    @episodes.size
  end
  
end

class Seasons
  
  attr_reader :serie
  
  def initialize(serie)
    @serie = serie
    @seasons = []
  end
  
  def getSeason(seasonnr) 
    @seasons.each do |s|
      if s.number == seasonnr
        return s
        break
      end
    end
    return nil
  end
  
  def add(episode)
    s = getSeason(episode.seasonno)
    if s.nil?
      s = Season.new(@serie, episode.seasonno) if s.nil?
      @seasons << s
    end
    s.add(episode)
  end

  def each
    0.upto(@seasons.length - 1) do |x|
      yield @seasons[x]
    end
  end
  
end

class Banner 
  attr_reader :path
  attr_reader :type
  attr_reader :type2
  attr_reader :hasname
  attr_reader :thumb
  attr_reader :vignette
  attr_reader :lang
  attr_reader :serie
  
  def initialize(serie, xml)
	  @serie = serie
	  @path = xml.elements['BannerPath'].text
	  @type = xml.elements['BannerType'].text
	  @type2 = xml.elements['BannerType2'].text
	  if xml.elements['SeriesName'].nil?
	    @hasname = false
	  else
	    @hasname = xml.elements['SeriesName'].text
    end
    @thumb = xml.elements['ThumbnailPath'].text unless xml.elements['SeriesName'].nil?
	  @vignette = xml.elements['VignettePath'].text unless xml.elements['VignettePath'].nil?
	  @lang = xml.elements['Language'].text unless xml.elements['Language'].nil?
	end
end

class Banners
  attr_reader :serie
  
  def initialize(serie)    
    @serie = serie
    @banners = []
    @banner_xml_path = Pathname.new "./series/banners.#{serie.id}.xml"
    if not @banner_xml_path.file? 
 		  banner_xml = get_banner_xml(serie.id)	
		  @banner_xml_path.open("w")  {|file| file.puts banner_xml}
		  @xmldoc = Document.new(banner_xml)
		else 
    	@banner_xml_path.open("r") {|file| @xmldoc = Document.new(file) }
    end
    load_banners()
  end
  
  def each
    0.upto(@banners.length - 1) do |x|
      yield @banners[x]
    end
  end
  
  def load_banners
    @xmldoc.elements.each('/Banners/Banner') do |b|
      @banners << Banner.new(self, b)
    end    
  end
  
  def get_banner_xml(id)
    puts id
		url = URI.parse('http://thetvdb.com')
		res = Net::HTTP.start(url.host, url.port) do |http|
		  http.get("/api/#{API_KEY}/series/#{id}/banners.xml")
		end
		doc = Document.new res.body
	end
	
end

class Serie
	attr_reader :name 
	attr_reader :overview
	attr_reader :first_aired
	attr_reader :airs_time
	attr_reader :poster
	attr_reader :banner
	attr_reader :id
	attr_reader :imdb
	attr_reader :seasons
	attr_reader :actors
	attr_reader :genres
	attr_reader :banners

	def initialize(id)
	  @tmpid = id
		@series_xml_path = Pathname.new "./series/#{id}.xml"
		
		if not @series_xml_path.file? 
 		  series_xml = get_series_xml()	
		  @series_xml_path.open("w")  { |file| file.puts series_xml }
    end
    @series_xml_path.open("r") {|file| @xmldoc = Document.new(file) }
		@name = @xmldoc.elements["/Data/Series/SeriesName"].text
		@id = @xmldoc.elements["/Data/Series/id"].text
		@overview = @xmldoc.elements["/Data/Series/Overview"].text
		@poster = @xmldoc.elements["/Data/Series/poster"].text
		@banner = @xmldoc.elements["/Data/Series/banner"].text
		@first_aired = DateTime.parse(@xmldoc.elements["/Data/Series/FirstAired"].text)
		@airs_at = DateTime.parse(@xmldoc.elements["/Data/Series/Airs_Time"].text)
		
		genres = @xmldoc.elements["/Data/Series/Genre"].text
		@genres = genres.split('|').select{|a| !a.nil? && !a.empty?} if genres && genres.is_a?(String) && !genres.empty?
		
		actors = @xmldoc.elements["/Data/Series/Actors"].text
		@actors = actors.split('|').select{|a| !a.nil? && !a.empty?} if actors && actors.is_a?(String) && !actors.empty?
    
    @banners = Banners.new(self)
    @seasons = Seasons.new(self)
    	  
		load_episodes()
	end

  def load_episodes
    @xmldoc.elements.each('/Data/Episode') do |ep|
 	    @seasons.add(Episode.new(self, ep))
    end    
  end

	def get_series_xml()
		url = URI.parse('http://thetvdb.com')
		res = Net::HTTP.start(url.host, url.port) do |http|
		  http.get("/api/#{API_KEY}/series/#{@tmpid}/all/en.xml")
		end
		doc = Document.new res.body
	end

end 

class Episode
	attr_reader :name 
  attr_reader :serie
  attr_reader :number
  attr_reader :seasonno
  attr_reader :id
  attr_reader :first_aired
  attr_reader :image
  attr_reader :overview
  attr_reader :guests
  attr_accessor :season
  
	def initialize(serie, xml)
	  @serie = serie
	  @name = xml.elements['EpisodeName'].text
	  @seasonno = xml.elements['SeasonNumber'].text
	  @number = xml.elements['EpisodeNumber'].text
	  @id = xml.elements['id'].text
	  @first_aired = xml.elements['FirstAired'].text
	  @image = xml.elements['filename'].text
	  @overview = xml.elements['Overview'].text
	  guests = xml.elements["GuestStars"].text
		@guests = guests.split('|').select{|a| !a.nil? && !a.empty?} if guests && guests.is_a?(String) && !guests.empty?
	end
end 