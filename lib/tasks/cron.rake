namespace :cron do
  desc "Tasks that should run hourly"
  task hourly: [:finish_projects, :second_slip_notification,
                :refresh_materialized_views, :schedule_reminders, :sync_fb_friends]

  desc "Tasks that should run daily"
  task daily: [ :notify_owners_of_deadline, :notify_project_owner_about_new_confirmed_contributions,
               :verify_pagarme_transactions, :notify_new_follows,
               :verify_pagarme_transfers, :verify_pagarme_user_transfers, :notify_pending_refunds, :request_direct_refund_for_failed_refund, :notify_expiring_rewards,
               :update_fb_users]

  desc "Refresh statistics materialized views"
  task refresh_stats_materialized_view: :environment do
    def refresh_views view_name
      begin
        only_view = view_name.split('.').try(:[], 1)
        ActiveRecord::Base.connection.execute(%Q{
          DO language plpgsql $$
             BEGIN
              IF NOT EXISTS (SELECT true FROM pg_stat_activity WHERE pg_backend_pid() <> pid AND query ~* 'refresh materialized .*#{only_view}') THEN
                 REFRESH MATERIALIZED VIEW CONCURRENTLY #{view_name};
              END IF;
             END;
          $$;
        })
      rescue => e
        puts e.inspect
        Raven.capture_exception(e)
      end
    end

    views = %w(
      public.moments_project_start public.moments_project_start_inferuser
      stats.project_points
      stats.aarrr_realizador_draft_projetos #A ordem aqui importa!
      stats.aarrr_realizador_online_projetos
      stats.aarrr_realizador_draft_by_category
      stats.aarrr_realizador_draft
      stats.aarrr_realizador_online_by_category
      stats.aarrr_realizador_online
      stats.growth_project_tags_weekly_contribs_mat #A ordem aqui importa!
      stats.growth_project_views
      stats.growth_contributions
      stats.growth_contributions_confirmed
      stats.growth_analise_tipo
      stats.financeiro_control_panel_simplificado
      stats.financeiro_int_payments_2016_simplificado
      stats.financeiro_payment_refund_error_distribution
      stats.financeiro_status_pagarme_catarse
      '"1".statistics' '"1".statistics_music' '"1".statistics_publicacoes')
    views.each do |v|
      refresh_views(v)
    end
  end

  desc "Refresh all materialized views"
  task refresh_materialized_views: :environment do
    puts "refreshing views"
    Statistics.refresh_view
    UserTotal.refresh_view
    CategoryTotal.refresh_view
    ActiveRecord::Base.connection.
      execute('REFRESH MATERIALIZED VIEW CONCURRENTLY "1".successful_projects') rescue nil
    ActiveRecord::Base.connection.
      execute('REFRESH MATERIALIZED VIEW CONCURRENTLY "1".finished_projects') rescue nil
    ActiveRecord::Base.connection.
      execute('REFRESH MATERIALIZED VIEW CONCURRENTLY public.moments_navigations') rescue nil
    ActiveRecord::Base.connection.
      execute('REFRESH MATERIALIZED VIEW CONCURRENTLY "1".project_visitors_per_day') rescue nil #depende do moments_navigations
  end

  desc 'Request refund for failed credit card refunds'
  task request_direct_refund_for_failed_refund: :environment do
    ContributionDetail.where("state in ('pending', 'paid') and project_state = 'failed' and lower(gateway) = 'pagarme' and lower(payment_method) = 'cartaodecredito'").each do |c|
      c.direct_refund
      puts "request refund for gateway_id -> #{c.gateway_id}"
    end
  end

  desc 'Notify about rewards about to expire'
  task notify_expiring_rewards: :environment do
    FlexibleProject.with_expiring_rewards.find_each do |project|
      puts "notifying about expiring rewards -> #{project.id}"
      project.notify(
        :expiring_rewards,
        project.user
      )
    end
  end

  desc 'Send pending balance transfer confirmation notifications'
  task sent_balance_transfer_reminders: [:environment] do
    Project.pending_balance_confirmation.each do |project| 
      Rails.logger.info "Notifying #{project.permalink} -> pending_balance_transfer_confirmation"
      project.notify(:pending_balance_transfer_confirmation, project.user)
    end
  end

  desc 'Notify projects with no deadline 1 week before max deadline'
  task notify_owners_of_deadline: :environment do
    Project.with_state(:online).where(online_days: nil).where("current_timestamp > online_at(projects.*) + '358 days'::interval").find_each do |project|
      project.notify_once(
        'project_deadline',
        project.user,
        project)
    end
  end

  desc 'Add reminder to scheduler'
  task schedule_reminders: :environment do
    ProjectReminder.can_deliver.find_each do |reminder|
      puts "found reminder for user -> #{reminder.user_id} project -> #{reminder.project}"
      project = reminder.project
      project.notify_once(
        'reminder',
        reminder.user,
        project)
    end
  end

  desc "Send second slip notification"
  task second_slip_notification: :environment do
    puts "sending second slip notification"
    ContributionDetail.slips_past_waiting.no_confirmed_contributions_on_project.each do |contribution_detail|
      contribution_detail.contribution.notify_to_contributor(:contribution_canceled_slip)
    end
  end

  desc "Finish all expired projects"
  task finish_projects: :environment do
    puts "Finishing projects..."
    Project.to_finish.each do |project|
      CampaignFinisherWorker.perform_async(project.id)
    end
  end

  desc "Send a notification to all project owners with contributions done..."
  task notify_project_owner_about_new_confirmed_contributions: :environment do
    puts "Notifying project owners about contributions..."
    Project.in_funding.with_contributions_confirmed_last_day.each do |project|
      # We cannot use notify_owner for it's a notify_once and we need a notify
      project.notify(
        :project_owner_contribution_confirmed,
        project.user
      )
    end
  end

  desc 'Send a notification about new contributions from friends'
  task notify_new_friends_contributions: [:environment] do
    User.with_contributing_friends_since_last_day.uniq.each do |user|
      user.notify(:new_friends_contributions) if user.subscribed_to_friends_contributions
    end
  end

  desc 'Send a notification about new follows'
  task notify_new_follows: [:environment] do
    User.followed_since_last_day.each do |user|
      user.notify(:new_followers) if user.subscribed_to_new_followers
    end
  end

  desc 'Send a notification about pending refunds'
  task notify_pending_refunds: [:environment] do
    Contribution.need_notify_about_pending_refund.each do |contribution|
     contribution.notify(:contribution_project_unsuccessful_slip_no_account,
                         contribution.user) unless contribution.user.bank_account.present?
    end
  end

  desc 'Update all fb users'
  task update_fb_users: [:environment] do
    User.joins(:projects).uniq.where("users.fb_parsed_link~'^pages/\\d+$'").each do |u|
      FbPageCollectorWorker.perform_async(u.id)
    end
  end

  desc 'sync FB friends'
  task sync_fb_friends: [:environment] do
    Authorization.where("last_token is not null and updated_at >= current_timestamp - '24 hours'::interval").each do |authorization|
      last_f = UserFriend.where(user_id: authorization.user_id).last
      next if last_f.present? && last_f.created_at > 24.hours.ago

      begin
        koala = Koala::Facebook::API.new(authorization.last_token)
        friends = koala.get_connections("me", "friends")

        friends.each do |f|
          friend_auth = Authorization.find_by_uid(f['id'])

          if friend_auth.present?
            puts "creating friend #{friend_auth.user_id} to user #{authorization.user_id}"
            UserFriend.create({
              user_id: authorization.user_id,
              friend_id: friend_auth.user_id
            })
          end
        end
      rescue Exception => e
        puts "error #{e}"
      end
    end
  end

end
