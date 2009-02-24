#!/usr/bin/env ruby
# vimtips2help.rb -- Convert a vimtips xml dump to tagged vim help
# @Author:      Thomas Link (micathom AT gmail com)
# @License:     GPL (see http://www.gnu.org/licenses/gpl.txt)
# @Created:     2009-02-23.
# @Last Change: 2009-02-24.

require 'hpricot'
require 'cgi'

require 'optparse'
require 'rbconfig'
require 'logger'


class Vimtips2Help

    APPNAME = 'vimtips'
    VERSION = '1.0.47'
    WIDTH = 72
    SHIFT = 4
    INDENT = ' ' * SHIFT


    class AppLog
        def initialize(output=$stdout)
            @output = output
            $logger = Logger.new(output)
            $logger.progname = defined?(APPNAME) ? APPNAME : File.basename($0, '.*')
            $logger.datetime_format = "%H:%M:%S"
            AppLog.set_level
        end
    
        def self.set_level
            if $DEBUG
                $logger.level = Logger::DEBUG
            elsif $VERBOSE
                $logger.level = Logger::WARN
            else
                $logger.level = Logger::INFO
            end
        end
    end


    class << self
    
        def with_args(args)
    
            AppLog.new
    
            config = Hash.new
            config[:xml] = 'pages_current.xml'
            config[:out] = 'vimtips.txt'
            config[:convert_unintentional_tags] = true
    
            opts = OptionParser.new do |opts|
                opts.banner =  "Usage: #{File.basename($0)} [OPTIONS]"
                opts.separator ' '
                opts.separator 'vimtips2help is a free software with ABSOLUTELY NO WARRANTY under'
                opts.separator 'the terms of the GNU General Public License version 2 or newer.'
                opts.separator ' '
            
                opts.separator 'General Options:'

                opts.on('-o', '--out FILENAME', String, "Output filename (default: #{config[:out]})") do |value|
                    config[:out] = value
                end

                opts.on('-t', 'Convert unintentional tags') do |bool|
                    config[:convert_unintentional_tags] = bool
                end

                opts.on('--xml FILENAME', String, "XML dump (default: #{config[:xml]})") do |value|
                    config[:xml] = value
                end
                
                opts.separator ' '
                opts.separator 'Other Options:'
            
                opts.on('--debug', 'Show debug messages') do |v|
                    $DEBUG   = true
                    $VERBOSE = true
                    AppLog.set_level
                end
            
                opts.on('-v', '--verbose', 'Run verbosely, display progress') do |v|
                    $VERBOSE = true
                    AppLog.set_level
                end
            
                opts.on_tail('-h', '--help', 'Show this message') do
                    puts opts
                    exit 1
                end
            end
            $logger.debug "command-line arguments: #{args}"
            argv = opts.parse!(args)
            $logger.debug "config: #{config}"
            $logger.debug "argv: #{argv}"
    
            return Vimtips2Help.new(config)
    
        end
    
    end


    def initialize(config)
        @config   = config
        @xml_file = config[:xml]
        @out_file = config[:out]
        @pages = []
        @blacklist = [
            /^(User|Forum|Image|Help|Category|MediaWiki|Template)( talk)?:/,
            /^Talk:/,
            /^Vim Tips Wiki/,
            /^NewCategoryIntro/,
            /^(News|Other Pages|Main Page|Sandbox|Tip Guidelines)$/,
            /^From Vim Help\/\d+$/,
            /^Did you know\/\d+$/,
        ]
    end


    def process
        collect_pages
        output_pages
    end


    protected

    def collect_pages
        doc = File.open(@xml_file) {|io| Hpricot.XML(io)}
        (doc/'page').each do |page|
            title = page.at('title')
            unless !title or @blacklist.any? {|rx| title.inner_html =~ rx}
                print '.'; STDOUT.flush if $VERBOSE
                @pages << {
                    :title => clean_markup(title.inner_html),
                    :text  => clean_markup(page.at('/revision/text').inner_html),
                }
            end
        end
        self
    end


    def output_pages
        File.open(@out_file, 'w') do |io|
            io.puts <<HEADER
*vimtips.txt*   All the vimtips you need
                #{File.ctime(@xml_file)}


CAVEAT: During conversion text matching " *TEXT* " was replaced with
" *TEXT*�" in order to avoid "Duplicate tag" messages when running 
helptags. This is relevant for a few code snippets that cannot be 
re-used unmodified (it should be save to do %s/\*�/* /). Run 
vimtips2help with the -t command-line option to prevent this conversion.


TABLE OF CONTENTS~

HEADER
            @pages.sort_by {|p| p[:title]}.each do |page|
                if page[:title] !~ /^VimTip\d+$/
                    tag = tag_name(page[:title], '|')
                    if page[:title].size + tag.size + 10 < WIDTH
                        io.puts "    #{page[:title]} #{'.' * [3, WIDTH - 6 - page[:title].size - tag.size].max} #{tag}"
                    else
                        io.puts "    #{page[:title]}"
                        io.puts "        #{'.' * [3, WIDTH - 9 - tag.size].max} #{tag}"
                    end
                end
            end
            io.puts
            io.puts

            @pages.each do |page|
                if page[:text] =~ /\S/
                    io.puts "=" * WIDTH
                    tag = tag_name(page[:title])
                    io.puts "#{' ' * [10, WIDTH - tag.size].max}#{tag}"
                    io.puts "#{page[:title]}~\n\n"
                    io.puts page[:text]
                    io.puts
                    io.puts
                end
            end
        end
        self
    end


    def tag_name(title, marker='*')
        tag = title.gsub(/\s+/, '-')
        # tag.gsub!(/[*'"^&(){}\[\]]/, '_')
        tag.gsub!(/[^a-zA-Z0-9_-]/, '_')
        "#{marker}tip-#{tag}#{marker}"
    end


    def clean_markup(text)
        text = CGI.unescapeHTML(text)
        text.gsub!(/<!-- \*+ -->/, '-' * WIDTH)
        text.gsub!(/<!--.*?-->/, '')
        text.gsub!(/:\n +/m, ":\n\n ")
        text.gsub!(/^ +/, INDENT)
        text.gsub!(/^\*(\S)/, "#{INDENT}- \\1")
        text.gsub!(/(\s)\*(\S+?)\*(\s)/, '\\1*\\2*�') if @config[:convert_unintentional_tags]
        text.gsub!(/\{\{script\|id=(\d+)(\|.*?)?\}\}/, 'vimscript#\\1')
        text.gsub!(/\{\{help\|(.*?)\}\}/) do
            t = $1
            if $1 =~ /^'.*?'$/
                t
            else
                "|#{t}|"
            end
        end
        text.gsub!(/^;\s?(.*)\s*\n?:\s?/, "#{INDENT}\\1::\n#{INDENT * 2}")
        # text.gsub!(/^;\s?(.*)\s*$\n(^:\s?.*?$\n)+/m) do
        #     desc = $2.each_line.map {|l| l.sub(/^:\s?/, INDENT * 2)}
        #     "#{INDENT}\\1::\n#{desc}"
        # end
        text.gsub!(/__NOTOC__/, '')
        text.gsub!(/\[\[User:.*?\]\] \d+:\d+, \d+ \w+ \d+ (UTC)/, '')
        text.gsub!(/\[\[VimTip\d+\|(\d+ )?(.*?)\]\]/) do
            tag_name($2, '|')
        end
        text.gsub!(/\[\[.*?\|(.*?)\]\]/, '\\1')
        text.gsub!(/\[\[(.*?)\]\]/) do
            tag_name($1, '|')
        end
        text.gsub!(/(--+)?<div id="wikia-credits">.*?<\/div>/, '')
        text.gsub!(/\{\{.*?\}\}\n?/m, '')
        text.gsub!(/<pre>\n(.*?)\n<\/pre>/m) do
            ">\n#{$1.each_line.map {|l| "#{INDENT}#{l}"}}\n<"
        end
        text.gsub!(/<tt>(.*?)<\/tt>/, '"\\1"')
        text.gsub!(/<i>(.*?)<\/i>/, '_\\1_')
        text.gsub!(/<code>(.*?)<\/code>/, '|\\1|')
        text.gsub!(/<\/?(br|code|nowiki)\/?>/, '')
        text.gsub!(/''+(.*?)''+/, '"\\1"')
        text.gsub!(/^==+(.*?)==+$/, "\n\\1~\n")
        text.gsub!(/^----+$/, '-' * WIDTH)
        text.sub!(/^Comments~\n\s*\Z/, '')

        return wrap(text)
    end


    def wrap(text)
        wrap = /^.{0,#{WIDTH - 10}}\S*\s*/
        acc = []
        text.each_line do |line|
            indent = /^ +/.match(line)
            indent = indent ? indent[0] : ''
            until line.empty?
                m = wrap.match(line)
                t = m[0]
                if t.size < 60
                    acc << t
                    break
                else
                    acc << "#{t} \n"
                end
                if m.post_match.empty?
                    line = ''
                else
                    line = "#{indent}#{m.post_match}"
                end
            end
        end
        acc.join()
    end

end


if __FILE__ == $0
    Vimtips2Help.with_args(ARGV).process
end


# Local Variables:
# revisionRx: VERSION\s\+=\s\+\'
# End: