Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', "delayed_job_#{Rails.env}.log"))
Delayed::Worker.logger.level = Rails.logger.level
