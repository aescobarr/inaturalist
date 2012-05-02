class Update < ActiveRecord::Base
  belongs_to :subscriber, :class_name => "User"
  belongs_to :resource, :polymorphic => true
  belongs_to :notifier, :polymorphic => true
  
  validates_uniqueness_of :notifier_id, :scope => [:notifier_type, :subscriber_id, :notification]
  
  NOTIFICATIONS = %w(create change activity)
  
  def resource_owner
    resource && resource.respond_to?(:user) ? resource.user : nil
  end
  
  def sort_by_date
    created_at || notifier.try(:created_at) || Time.now
  end
  
  def self.group_and_sort(updates)
    grouped_updates = []
    updates.group_by{|u| [u.resource_type, u.resource_id, u.notification]}.each do |key, batch|
      resource_type, resource_id, notification = key
      batch = batch.sort_by{|u| u.sort_by_date}
      if notification == "created_observations" && batch.size > 1
        batch.group_by{|u| u.created_at.strftime("%Y-%m-%d %H")}.each do |hour, hour_updates|
          grouped_updates << [key, hour_updates]
        end
      elsif notification == "activity"
        # get the reousrce that has all this activity
        resource = Object.const_get(resource_type).find_by_id(resource_id)
        
        # get the associations on that resource that generate activity updates
        activity_assocs = resource.class.notifying_associations.select do |assoc, assoc_options|
          assoc_options[:notification] == "activity"
        end
        
        # create pseudo updates for all activity objects
        activity_assocs.each do |assoc, assoc_options|
          # this is going to lazy load assoc's of the associate (e.g. a comment's user) which might not be ideal
          resource.send(assoc).each do |associate|
            unless batch.detect{|u| u.notifier == associate}
              batch << Update.new(:resource => resource, :notifier => associate, :notification => "activity")
            end
          end
        end
        grouped_updates << [key, batch.sort_by{|u| u.sort_by_date}]
      else
        grouped_updates << [key, batch]
      end
    end
    grouped_updates.sort_by {|key, updates| updates.last.sort_by_date.to_i * -1}
  end
  
  def self.email_updates
    Rails.logger.info "[INFO #{Time.now}] start daily updates emailer"
    start_time = 1.day.ago.utc
    end_time = Time.now.utc
    email_count = 0
    user_ids = Update.all(
        :select => "DISTINCT subscriber_id",
        :conditions => ["created_at BETWEEN ? AND ?", start_time, end_time]).map{|u| u.subscriber_id}.compact
    user_ids.each do |subscriber_id|
      if email_updates_to_user(subscriber_id, start_time, end_time)
        email_count += 1
      end
    end
    Rails.logger.info "[INFO #{Time.now}] end daily updates emailer, sent #{email_count} in #{Time.now - end_time} s"
  end
  
  def self.email_updates_to_user(subscriber, start_time, end_time)
    user = User.find_by_id(subscriber.to_i) unless subscriber.is_a?(User)
    user ||= User.find_by_login(subscriber)
    return unless user
    return if user.email.blank?
    return unless user.active? # email verified
    return unless user.admin? # testing
    updates = Update.all(:conditions => ["subscriber_id = ? AND created_at BETWEEN ? AND ?", user.id, start_time, end_time])
    updates.delete_if do |u| 
      !user.prefers_comment_email_notification? && u.notifier_type == "Comment" ||
      !user.prefers_identification_email_notification? && u.notifier_type == "Identification"
    end.compact
    return if updates.blank?
    Emailer.deliver_updates_notification(user, updates)
    true
  end
  
  def self.eager_load_associates(updates, options = {})
    includes = options[:includes] || {
      :observation => [:user, {:taxon => :taxon_names}, :iconic_taxon, :photos],
      :identification => [:user, {:taxon => [:taxon_names, :photos]}, {:observation => :user}],
      :comment => [:user, :parent],
      :listed_taxon => [{:list => :user}, {:taxon => [:photos, :taxon_names]}]
    }
    update_cache = {}
    [Comment, Identification, Observation, ListedTaxon, Post].each do |klass|
      ids = updates.map do |u|
        if u.notifier_type == klass.to_s
          u.notifier_id
        elsif u.resource_type == klass.to_s
          u.resource_id
        else
          nil
        end
      end.compact
      update_cache[klass.to_s.underscore.pluralize.to_sym] = klass.all(
        :conditions => ["id IN (?)", ids], 
        :include => includes[klass.to_s.underscore.to_sym]
      ).index_by{|o| o.id}
    end
    update_cache
  end
end
