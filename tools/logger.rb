require 'json'
require 'csv'
require 'optparse'
require 'time'

class LatencyReportFormatter
  VERSION = "1.0.0"

  def initialize(input_path, output_path, format)
    @input_path = input_path
    @output_path = output_path
    @format = format.downcase
    @data = []
  end

  def load_data
    unless File.exist?(@input_path)
      puts "Error: Input file #{@input_path} not found."
      exit 1
    end

    raw_content = File.read(@input_path).strip
    @data = JSON.parse(raw_content)
  rescue JSON::ParserError => e
    puts "Error parsing JSON data: #{e.message}"
    exit 1
  end

  def process
    load_data
    
    case @format
    when 'csv'
      export_csv
    when 'json'
      export_json
    when 'md', 'markdown'
      export_markdown
    else
      puts "Unsupported format: #{@format}"
      exit 1
    end
    
    puts "Report successfully exported to #{@output_path}"
  end

  private

  def calculate_statistics
    latencies = @data.map { |entry| entry['latency_ms'].to_f }.sort
    return {} if latencies.empty?

    {
      count: latencies.size,
      min: latencies.first.round(4),
      max: latencies.last.round(4),
      avg: (latencies.sum / latencies.size).round(4),
      p50: latencies[(latencies.size * 0.50).to_i].round(4),
      p95: latencies[(latencies.size * 0.95).to_i].round(4),
      p99: latencies[(latencies.size * 0.99).to_i].round(4),
      std_dev: Math.sqrt(latencies.map { |l| (l - (latencies.sum / latencies.size))**2 }.sum / latencies.size).round(4)
    }
  end

  def export_csv
    CSV.open(@output_path, "wb") do |csv|
      csv << ["timestamp", "kernel", "backend", "latency_ms", "jitter"]
      @data.each do |row|
        csv << [row['timestamp'], row['kernel'], row['backend'], row['latency_ms'], row['jitter']]
      end
    end
  end

  def export_json
    stats = calculate_statistics
    output = {
      metadata: {
        generated_at: Time.now.iso8601,
        tool: "Biometric Latency Cartographer Logger",
        version: VERSION
      },
      statistics: stats,
      raw_measurements: @data
    }
    File.write(@output_path, JSON.pretty_generate(output))
  end

  def export_markdown
    stats = calculate_statistics
    
    report = <<~MARKDOWN
      # Biometric Latency Cartographer Report
      Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      ## Summary Statistics
      | Metric | Value (ms) |
      | :--- | :--- |
      | Sample Count | #{stats[:count]} |
      | Minimum | #{stats[:min]} |
      | Average | #{stats[:avg]} |
      | Median (P50) | #{stats[:p50]} |
      | P95 | #{stats[:p95]} |
      | P99 | #{stats[:p99]} |
      | Maximum | #{stats[:max]} |
      | Std Deviation | #{stats[:std_dev]} |

      ## Hardware & Environment
      - **Kernel identified:** #{@data.first['kernel'] rescue 'Unknown'}
      - **Rendering Backend:** #{@data.first['backend'] rescue 'Unknown'}

      ## Raw Data Preview
      | Timestamp | Latency (ms) | Jitter |
      | :--- | :--- | :--- |
    MARKDOWN

    @data.take(20).each do |row|
      report += "| #{row['timestamp']} | #{row['latency_ms']} | #{row['jitter']} |\n"
    end
    
    report += "\n*Total records: #{@data.size}*"
    File.write(@output_path, report)
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: logger.rb [options]"

  opts.on("-i", "--input FILE", "Path to raw input JSON measurement file") do |i|
    options[:input] = i
  end

  opts.on("-o", "--output FILE", "Path to save the processed report") do |o|
    options[:output] = o
  end

  opts.on("-f", "--format FORMAT", "Export format: csv, json, md") do |f|
    options[:format] = f
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

if options[:input] && options[:output] && options[:format]
  logger = LatencyReportFormatter.new(options[:input], options[:output], options[:format])
  logger.process
else
  puts "Missing required arguments. Run with --help for usage."
  exit 1
end