module Jobs
  # A daily job that will enqueue digest emails to be sent to users at fixed times
  # We do this because of time slides with queued jobs.
  # When they run they may start just before the hour and we skip the schedule.
  class EnqueueFixedDigestEmails < Jobs::Scheduled
    daily at: 0.hours

    def execute(args)
      if SiteSetting.fixed_digest_enabled?
        y = Time.now.utc.year
        m = Time.now.utc.month
        d = Time.now.utc.day
        z = timezone("America/New_York")

        [10,16].each do |h|
          Jobs.enqueue_at(Time.new(y, m, d, h, 0, 0, z), :process_fixed_digest, {})
        end
      end
    end

  end
end
