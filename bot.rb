require 'telegram/bot'
require 'httparty'
require 'uri'
require 'nokogiri'
require 'rufus-scheduler'
require 'yaml'

config = YAML.load_file('secrets.yml')

$token = config['API_TOKEN']
$channel_id = config['CHANNEL']
$authinfo = { username: config['USER'], password: config['PASS'] }
response = ''
scheduler = Rufus::Scheduler.new
$git_url = config['GIT_URL']
$project_id = config['PROJECT_ID']
$repo_name = config['REPO_NAME']
$branch_name = config['BRANCH_NAME']
frequency = config['FREQUENCY']
$latest_commit = $branch_name


def broadcast(file_path_list)
  message = "The following database related files have been modified. Please take note.\n#{file_path_list.join('\n ')}"
  backoff = 5
  loop do
    begin
      Telegram::Bot::Client.run($token) do |bot|
        bot.api.send_message(chat_id: $channel_id, text: message)
      end
      backoff = 0
    rescue Telegram::Bot::Exceptions::ResponseError => e
      p "#{Time.now} Failed to send message!"
      p e
      backoff *= 5
    end
    break if backoff == 0
  end
end

def fetch_json_changes
  p "fetching changes"
  response = HTTParty.get("#{$git_url}/rest/api/latest/projects/#{$project_id}/repos/#{$repo_name}/changes?os_authType=basic&since=#{$latest_commit}&until=#{$branch_name}", basic_auth: $authinfo)
  response.parsed_response.dig('values')
end

def check_for_migration_changes(change_list)
  p "checking files"
  file_path_list = []

  change_list.each do |item|
    file_path = item.dig('path', 'components').join('/')
    p "current file: #{file_path}"
    file_path_list << file_path if file_path.start_with?('db/migrate')
  end
  p "affected file_path_list #{file_path_list}"
  broadcast(file_path_list) unless file_path_list.empty?
end

def update_latest_commit_id
  response = HTTParty.get("#{$git_url}/rest/api/latest/projects/#{$project_id}/repos/#{$repo_name}/commits?os_authType=basic&until=#{$branch_name}", basic_auth: $authinfo)
  $latest_commit = response.parsed_response.dig('values').first['id']
  p "updating latest_commit to #{$latest_commit}"
end

scheduler.every frequency do
  check_for_migration_changes(fetch_json_changes)
  update_latest_commit_id
end

scheduler.join
