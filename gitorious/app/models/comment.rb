# encoding: utf-8
#--
#   Copyright (C) 2012-2013 Gitorious AS
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
#   Copyright (C) 2008 Johan Sørensen <johan@johansorensen.com>
#   Copyright (C) 2008 David A. Cuadrado <krawek@gmail.com>
#   Copyright (C) 2008 Tor Arne Vestbø <tavestbo@trolltech.com>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

class Comment < ActiveRecord::Base
  include Gitorious::Authorization

  belongs_to :user
  belongs_to :target, :polymorphic => true
  belongs_to :project
  has_many   :events, :as => :target, :dependent => :destroy
  after_create :notify_target_if_supported
  after_create :update_state_in_target
  serialize :state_change, Array
  attr_accessible(:sha1, :body, :path, :user, :project, :state_change, :lines,
                  :target, :target_id, :target_type)
  validates_presence_of :user_id, :target, :project_id
  validates_presence_of :body, :if =>  Proc.new {|mr| mr.body_required?}

  named_scope :with_shas, proc{|*shas|
    {:conditions => { :sha1 => shas.flatten }, :include => :user}
  }

  NOTIFICATION_TARGETS = [ MergeRequest, MergeRequestVersion ]

  def deliver_notification_to(another_user)
    message_body = "#{user.title} commented:\n\n#{body}"
    if [MergeRequest, MergeRequestVersion].include?(target.class)
      if state_change
        message_body << "\n\nThe status of your merge request"
        message_body << " is now #{state_changed_to}"
      end
      subject_class_name = "merge request"
    else
      subject_class_name = target.class.human_name.downcase
    end
    message = Message.new({
      :sender => self.user,
      :recipient => another_user,
      :subject => "#{user.title} commented on your #{subject_class_name}",
      :body => message_body,
      :notifiable => self.target,
    })
    message.save
  end

  def state=(new_state)
    return if new_state.blank?
    result = []
    if applies_to_merge_request?
      return if target.status_tag.to_s == new_state
      result << (target.status_tag.nil? ? nil : target.status_tag.name)
    end
    result << new_state
    self.state_change = result
  end

  def state_changed_to
    state_change.to_a.last
  end

  def state_changed_from
    state_change.to_a.size > 1 ? state_change.first : nil
  end

  def body_required?
    if applies_to_merge_request?
      return state_change.blank?
    else
      return true
    end
  end

  # +lines_str+ is a representation of the first and last line-number
  # tuple (as generated by Diff::Unified::Generator) and the lines the
  # comment span, in the follow format:
  # first_tuple:last_tuple+line_span
  def lines=(lines_str)
    start, rest = lines_str.split(":")
    raise "invalid lines format" if rest.blank?
    last, amount = rest.split("+")
    if start.blank? || last.blank? || amount.blank?
      raise "invalid lines format"
    end
    self.first_line_number = start
    self.last_line_number = last
    self.number_of_lines = amount
  end

  def lines
    "#{self.first_line_number}:#{self.last_line_number}+#{self.number_of_lines}"
  end

  def sha_range
    first, last = sha1.split("-")
    first..(last||first)
  end

  def applies_to_line_numbers?
    return !first_line_number.blank?
  end

  def applies_to_merge_request?
    MergeRequest === target
  end

  def creator?(a_user)
    a_user == user
  end

  def recently_created?
    created_at > 10.minutes.ago
  end

  protected
  def notify_target_if_supported
    if target && NOTIFICATION_TARGETS.include?(target.class)
      if self.target === MergeRequestVersion
        target_user = target.merge_request.user
      else
        target_user = target.user
      end
      return if target_user == user
      deliver_notification_to(target_user)
    end
  end

  def update_state_in_target
    if applies_to_merge_request? and state_change
      target.with_user(user) do
        if can_resolve_merge_request?(user, target)
          target.status_tag=(state_changed_to)
          target.create_status_change_event(body)
        end
      end
    end
  end
end
