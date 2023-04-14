every 5.minutes, roles: [:streamer]  do
  rake 'update_stats:all', output: './log/update_stats_all.log'
end

every 12.hours, roles: [:streamer]  do
  rake 'update_articles:less_2_days', output: './log/update_articles_less_2_days.log'
end

every 3.days, roles: [:streamer]  do
  rake 'update_articles:2_to_14_days', output: './log/update_articles_2_to_14_days.log'
end

every 1.month, roles: [:streamer]  do
  rake 'update_rank:all', output: './log/update_rank_all.log'
end

every 30.minutes, roles: [:streamer]  do
  rake 'update_publishers:update_banned', output: './log/update_publishers_update_banned.log'
end

# every 1.hour, roles: [:streamer]  do
#   rake 'update_tl:score', output: './log/update_tl_score.log'
# end

# 5:30am, 2:30am, 11:30pm
every '30 5,14,23 * * *', roles: [:delayed_job] do
  rake 'restart_queues:now', output: './log/restart_queues_now.log'
end

every 2.weeks, at: '2:00am', roles: [:streamer] do
  rake 'update_tl:all', output: './log/update_tl_all.log'
end
#
# every 1.hour, roles: [:streamer] do
#   rake 'generate_graph:all', output: './log/generate_graph_all.log'
# end

if @environment == 'production'
  every 1.day, roles: [:streamer] do
    rake 'backup:db', output: './log/backup_db.log'
  end

  every 12.hours, roles: [:streamer] do
    rake 'backup:ebs', output: './log/backup_ebs.log'
  end
end
