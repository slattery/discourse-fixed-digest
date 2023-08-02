module Jobs
  # A daily job that will enqueue digest emails to be sent to users at fixed times
  # We do this because of time slides with queued jobs.
  # When they run they may start just before the hour and we skip the schedule.
  # Time.new(y, m, d, h, 0, 0, z)
  # enqtime = t.to_datetime.change(zone: z, hour: h)
  # to_time checks ActiveSupport.to_time_preserves_timezone so...
  class EnqueueFixedDigestEmails < Jobs::Scheduled
    daily at: 6.hours

    def execute(args)
      if SiteSetting.fixed_digest_enabled?
        z = "America/New_York"
        t = Time.now.in_time_zone(z)
        
        [10,16].each do |h|
          enqtime = t.to_datetime.change(hour: h, min: 0).to_time.utc
          Jobs.enqueue_at(enqtime, :process_fixed_digest, {})
        end
      end
    end

  end
end
