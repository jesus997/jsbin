require 'optparse'
require 'simple_xlsx_reader'
require 'csv'

# Columns in the spreadsheet
# 13: Lang (en, es)
# 14: Origin (facebook, email, google)
# 15: Hotel (palmares, villarco, etc)
@options = {
  'filter_by' => 14,
  'roiback_db_path' => ''
}

OptionParser.new do |opts|
  opts.on('-f', '--filter-by [FILTER_BY]', 'Filter by column') do |filter_by|
    @options['filter_by'] = filter_by
  end
  opts.on('-r', '--roiback_db_path [ROIBACK_DB_PATH]', 'Roiback database file path') do |roiback_db_path|
    @options['roiback_db_path'] = roiback_db_path
  end
end.parse!

unless File.file?(@options['roiback_db_path'])
  puts "Error: #{@options['roiback_db_path']} is not a valid file"
  exit
end

registered_users = SimpleXlsxReader.open(@options['roiback_db_path'])
sheet1 = registered_users.sheets.first
rows = sheet1.rows

# Remove the first row
rows.shift if rows[0][14] == 'Origen alta'

# Iterate over the rows.
registered_by_provider = rows
  .group_by { |row| row[@options['filter_by']] }
  .to_h do |key, value|
  key = 'email' if key == 'roiback'
  [key, value.count]
end

registered_by_provider[:total] = registered_by_provider.reduce(0) { |s, a| s + a[1] }

# Print the results

print "----------------------------------------\n"
print "           Roiback users stats          \n"
print "----------------------------------------\n"
registered_by_provider.each do |key, value|
  printf "%-10s: %-4s new users\n", key.capitalize, value
end

print "\n" # for fix % to end
