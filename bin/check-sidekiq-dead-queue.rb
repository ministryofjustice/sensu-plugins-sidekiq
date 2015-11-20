#! /usr/bin/env ruby
# encoding: UTF-8

require 'sensu-plugin/check/cli'
require 'open-uri'
require 'json'
require 'time'
require 'date'
require 'timerizer'


# DESCRIPTION:
#   Check that the sidekiq dead queue size is 0 using the sidekiq
#   stats JSON page under
#   /sidekiq/dashboard/stats
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: open-uri
#   gem: json
#   gem: timerizer
#
# LICENSE:
#   by https://github.com/bennythejudge
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
class SidekiqCheck < Sensu::Plugin::Check::CLI
  option :url,
         short: '-u URL',
         long: '--url URL',
         description: 'Url to query',
         required: true

  option :auth,
         short: '-a USER:PASSWORD',
         long: '--auth USER:PASSWORD',
         description: 'Basic auth credentials if you need them',
         proc: proc { |auth| auth.split(':') }

  option :silence,
          short: '-sil START_TIME-NUMBER_OF_HOURS',
          long: '--silence START_TIME-NUMBER_OF_HOURS',
          description: 'Time period in 24h format to silence alerts',
          proc: proc { |period| period.split('-') }

  option :silence_weekends,
          short: '-sw true/false',
          long: '--silence-weekends true/false',
          description: 'Disables alerting for the dead queue during weekends'

  def run
    check_for_silence do
      begin
        stats = JSON.parse(
          if config[:auth]
            open(config[:url], http_basic_authentication: config[:auth]).read
          else
            open(config[:url]).read
          end
        )
      rescue => error
        unknown "Could not load Sidekiq stats from #{config[:url]}. Error: #{error}"
      end
      dead_queue_size = stats['sidekiq']['dead']
      if !dead_queue_size.zero?
        entry_or_entries =  dead_queue_size > 1 ? 'entries' : 'entry'
        critical 'dead queue not empty (' + dead_queue_size.to_s + ' ' + entry_or_entries + ')'
      else
        ok 'sidekiq dead queue is empty'
      end
    end
  end

  def check_for_silence(&block)
    now = Time.now.utc
    silence_weekends = !!config[:silence_weekends]
    if silence_weekends && weekend?
      ok 'silence mode - dead queue checks disabled for the weekend'
    elsif time_period && time_period.cover?(Time.now.utc)
      ok 'silence mode - dead queue checks disabled for time period'
    else
      yield
    end
  end

  private

  def weekend?
    day = Date.today.strftime('%a').downcase
    ['sat', 'sun'].include?(day)
  end

  def time_period
    start_time, hours = config[:silence]
    if start_time && hours
      start_hour = Time.parse(start_time).strftime('%H').to_i
      naive_end_hour = hours.to_i.hours.after(Time.parse(start_time)).strftime('%H').to_i

      start_time = start_hour > naive_end_hour ? previous_day(start_time) : today(start_time)
      end_time = hours.to_i.hours.after(start_time)
      (start_time..end_time)
    else
      nil
    end
  end

  def previous_day(start_time)
    yesterday = Time.parse(Date.today.prev_day.to_s)
    Time.parse(start_time, yesterday)
  end

  def today(start_time)
    Time.parse(start_time)
  end

end
