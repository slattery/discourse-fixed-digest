# frozen_string_literal: true

# name: discourse-fixed-digest
# about: Send a simple fixed interval digest on user defined schedule
# version: 0.1
# authors: slattery
# url: https://github.com/slattery/discourse-fixed-digest

# huge credit to https://github.com/joebuhlig for
# https://github.com/procourse/discourse-mlm-daily-summary
# which shows how to add a type to the std user_notification mailer

enabled_site_setting :fixed_digest_enabled

def local_require(path)
  require Rails.root.join('plugins', 'discourse-fixed-digest', path).to_s
end

after_initialize do

  register_editable_user_custom_field :fixed_digest_emails
  register_editable_user_custom_field :fixed_digest_deliveries

  User.register_custom_field_type 'fixed_digest_emails', :boolean

  DiscoursePluginRegistry.serialized_current_user_fields << 'fixed_digest_emails'
  DiscoursePluginRegistry.serialized_current_user_fields << 'fixed_digest_deliveries'

  # add function to NotificationLevels in order to safely add to std discourse enum
  # once the function is bolted on, use it to add web_only level
  # this way we will can have topics appear for user's home page but not email
  require_dependency 'notification_levels'

  module ::NotificationLevels
    def self.add_notification_level(name, id)
      @all_levels ||= self.all
      @all_levels[name] = id
    end
  end

  NotificationLevels.add_notification_level(:web_only, 100)

  # add fixed_digest message type to user_notifications

  local_require 'app/jobs/regular/process_fixed_digest'
  local_require 'app/jobs/scheduled/fixed_daily_digest'

  class ::UserNotifications
    def fixed_digest(user, opts = {})
      prepend_view_path(Rails.root.join('plugins', 'discourse-fixed-digest', 'app', 'views'))

      @since = 1.day.ago
      min_date = @since || user.last_emailed_at || user.last_seen_at || 1.month.ago
      min_date_str = min_date.to_s
      Rails.logger.warn("[FIXED SUMMARY]  entering digest func with #{min_date_str}")
      # Fetch some topics and posts to show
      digest_opts = { limit: SiteSetting.digest_topics + SiteSetting.digest_other_topics, top_order: true }
      web_only_exclusions = CategoryUser.where(user_id: user.id, notification_level: CategoryUser.notification_levels[:web_only]).pluck(:category_id)
      topics_for_digest = Topic.joins(:posts).includes(:posts).for_digest(user, 14.days.ago, digest_opts.merge(include_tl0: true)).where('posts.created_at > ?', min_date)
      if web_only_exclusions.present?
        topics_for_digest = topics_for_digest.where("topics.category_id NOT IN (?)", web_only_exclusions)
      end

      @latest_topics   = topics_for_digest.where("topics.created_at > ?", min_date).uniq.to_a
      @update_topics   = topics_for_digest.where("topics.created_at <= ?", min_date).uniq.to_a
      @topics          = topics_for_digest.uniq.to_a

      @recent_topics   = @latest_topics[0, SiteSetting.digest_topics]
      @active_topics   = @update_topics[0, SiteSetting.digest_topics]

      if @topics.present?

        @excerpts = {}

        if @recent_topics.present?
          @recent_topics.map do |t|
            @excerpts[t.first_post.id] = format_for_email(t.first_post, nil) if t.first_post.present?
          end
        end

        if @active_topics.present?
          @active_topics.map do |t|
            @excerpts[t.first_post.id] = format_for_email(t.first_post, nil) if t.first_post.present?
          end
        end

        @last_seen_at = short_date(user.last_seen_at || user.created_at)
        @preheader_text = I18n.t('user_notifications.fixed_digest.preheader', last_seen_at: @last_seen_at)

        build_summary_for(user)
        opts = {
          from_alias: I18n.t('user_notifications.fixed_digest.from', site_name: Email.site_title),
          subject: I18n.t('user_notifications.fixed_digest.subject_template', email_prefix: @email_prefix, date: short_date(Time.now)),
          add_unsubscribe_link: false,
          unsubscribe_url: "#{Discourse.base_url}/email/unsubscribe/#{@unsubscribe_key}",
        }

        build_email(user.email, opts)
      end
    end
  end

end
