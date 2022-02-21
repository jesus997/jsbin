require 'optparse'
require 'simple_xlsx_reader'
require 'csv'

# Columns in the spreadsheet
# 13: Lang (en, es)
# 14: Origin (facebook, email, google)
# 15: Hotel (palmares, villarco, etc)
@options = {
  'filter_by' => 14,
  'db_path' => '',
  'roiback_db_path' => ''
}

OptionParser.new do |opts|
  opts.on('-f', '--filter-by [FILTER_BY]', 'Filter by column') do |filter_by|
    @options['filter_by'] = filter_by
  end
  opts.on('-d', '--db-path [DB_PATH]', 'Local database file path') do |db_path|
    @options['db_path'] = db_path
  end
  opts.on('-r', '--roiback_db_path [ROIBACK_DB_PATH]', 'Roiback database file path') do |roiback_db_path|
    @options['roiback_db_path'] = roiback_db_path
  end
end.parse!

# Check if @options['db_path'] and @options['roiback_db_path'] is a valid file
unless File.file?(@options['db_path'])
  puts "Error: #{@options['db_path']} is not a valid file"
  exit
end

unless File.file?(@options['roiback_db_path'])
  puts "Error: #{@options['roiback_db_path']} is not a valid file"
  exit
end

printf "Reminder: %s is updated?\n", @options['db_path']

db_users = CSV.parse(File.read(@options['db_path']).scrub)
db_emails = db_users.map { |row| row[1] }

registered_users = SimpleXlsxReader.open(@options['roiback_db_path'])
sheet1 = registered_users.sheets.first
rows = sheet1.rows

# Remove the first row
rows.shift if rows[0][14] == 'Origen alta'

# Get all emails
emails_registered = rows.map { |row| row[4] }
emails_registered -= db_emails

# Iterate over the rows.
registered_by_provider = rows
                         .filter { |row| !emails_registered.include?(row[4]) }
                         .group_by { |row| row[@options['filter_by']] }
                         .map do |key, value|
  key = 'email' if key == 'roiback'
  [key, value.count]
end.to_h

registered_by_provider[:total] = registered_by_provider.values.reduce(:+)

# Print the results

print "----------------------------------------\n"
print "           Roiback users stats          \n"
print "----------------------------------------\n"
registered_by_provider.each do |key, value|
  printf "%-10s: %-4s new users\n", key.capitalize, value
end

print "\n" # for fix % to end
