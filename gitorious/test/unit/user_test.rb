# encoding: utf-8
#--
#   Copyright (C) 2012-2013 Gitorious AS
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
#   Copyright (C) 2007 Johan Sørensen <johan@johansorensen.com>
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

require File.dirname(__FILE__) + "/../test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.new
  end

  should "create a valid user" do
    assert_difference("User.count") do
      user = create_user
      assert !user.new_record?
    end
  end

  should_have_many :email_aliases
  should_have_many :committerships, :dependent => :destroy
  should_have_many :memberships, :dependent => :destroy
  should_have_many :email_aliases, :dependent => :destroy
  should_have_many :commit_repositories
  should_have_many :favorites, :dependent => :destroy
  should_have_many :feed_items

  should_validate_presence_of :login, :password, :password_confirmation, :email
  should_validate_acceptance_of :terms_of_use

  should_not_allow_values_for :login, "john.doe", "john_doe"
  should_allow_values_for :login, "JohnDoe", "john-doe", "john999"

  should "downcase the login before validation" do
    u = User.new
    u.login = "FooBar"
    assert !u.valid?
    assert_equal("foobar", u.login)
  end

  should "require a username without spaces" do
    assert_no_difference("User.count") do
      u = create_user(:login => "joe schmoe")
      assert_equal "is invalid", u.errors.on(:login)
    end
  end

  should "require an email that looks emailish" do
    assert_no_difference("User.count") do
      u = create_user(:email => "kernel.wtf")
      assert_not_nil u.errors.on(:email)
    end
  end

  should "accept co.uk and the like" do
    assert_difference("User.count") do
      u = create_user(:email => "ker+nel.w-t-f@foo-bar.co.uk")
      assert u.valid?
    end
  end

  should "not send activation mail when user is already activated" do
    Mailer.expects(:deliver_signup_notification).never
    u = User.new({ :email => "quire@example.com" })
    u.terms_of_use = "1"
    u.aasm_state = "pending"
    u.login = "quire"
    u.password = u.password_confirmation = "quire"
    u.activated_at = Time.now
    u.activation_code = nil

    u.save!
  end

  should "reset password" do
    user = users(:johan)
    user.password = "newpass"
    user.password_confirmation = "newpass"
    user.save

    assert_equal users(:johan), User.authenticate("johan@johansorensen.com", "newpass")
  end

  should "not rehash the password" do
    users(:johan).update_attributes(:email => "johan2@js.com")
    assert_equal users(:johan), User.authenticate("johan2@js.com", "test")
  end

  should "authenticate user" do
    assert_equal users(:johan), User.authenticate("johan@johansorensen.com", "test")
  end

  should "set remember token" do
    users(:johan).remember_me
    assert_not_nil users(:johan).remember_token
    assert_not_nil users(:johan).remember_token_expires_at
  end

  should "unset remember token" do
    users(:johan).remember_me
    assert_not_nil users(:johan).remember_token
    users(:johan).forget_me
    assert_nil users(:johan).remember_token
  end

  should "remember user for one week" do
    before = 1.week.from_now.utc
    users(:johan).remember_me_for 1.week
    after = 1.week.from_now.utc
    assert_not_nil users(:johan).remember_token
    assert_not_nil users(:johan).remember_token_expires_at
    assert users(:johan).remember_token_expires_at.between?(before, after)
  end

  should "remember me until one week later" do
    time = 1.week.from_now.utc
    users(:johan).remember_me_until time
    assert_not_nil users(:johan).remember_token
    assert_not_nil users(:johan).remember_token_expires_at
    assert_equal time, users(:johan).remember_token_expires_at
  end

  should "remember me default two weeks" do
    before = 2.weeks.from_now.utc
    users(:johan).remember_me
    after = 2.weeks.from_now.utc
    assert_not_nil users(:johan).remember_token
    assert_not_nil users(:johan).remember_token_expires_at
    assert users(:johan).remember_token_expires_at.between?(before, after)
  end

  should "know if a user has write access to a repository" do
    u = users(:mike)
    repo = repositories(:johans2)
    assert can_push?(u, repo)
    assert !can_push?(users(:johan), repo)
    repo.owner.add_member(users(:johan), Role.member)
    repo.reload
    assert committers(repo).include?(users(:johan))
    assert can_push?(users(:johan), repo)
  end

  should "not have wiki repositories in #repositories" do
    assert !users(:johan).repositories.include?(repositories(:johans_wiki))
  end

  should "have the login as to_param" do
    assert_equal users(:johan).login, users(:johan).to_param
  end

  should "find a user by login or raises" do
    assert_equal users(:johan), User.find_by_login!(users(:johan).login)
    assert_raises(ActiveRecord::RecordNotFound) do
      User.find_by_login!("asdasdasd")
    end
  end

  should "generate some random password" do
    assert_match(/\w+/, User.generate_random_password)
    assert_equal 24, User.generate_random_password.length
    assert_equal 32, User.generate_random_password(16).length
    assert_equal 10, User.generate_random_password(5).length
  end

  should "reset a password to something" do
    u = users(:johan)
    password = u.reset_password!
    assert_equal u, User.authenticate(u.email, password)
  end

  should "set the password key with forgot_password!" do
    u  = users(:johan)
    key = u.forgot_password!
    assert_equal key, u.reload.password_key
  end

  should "normalize identity urls" do
    u = users(:johan)
    u.identity_url = "http://johan.someprovider.com"
    assert u.valid?
    assert_equal "http://johan.someprovider.com/", u.identity_url

    u.identity_url = "http://johan.someprovider.com/me"
    assert u.valid?
    assert_equal "http://johan.someprovider.com/me", u.identity_url
  end

  should "catch invalid identity_url" do
    u = users(:johan)
    u.identity_url = "€&/()"
    assert !u.valid?
    assert_not_nil u.errors.on(:identity_url), u.errors.on(:identity_url)
  end

  should "return that the user already has a password" do
    u = users(:johan)
    assert !u.is_openid_only?
  end

  should "return an grit actor object" do
    js = users(:johan)
    actor = js.to_grit_actor
    assert_instance_of Grit::Actor, actor
    assert_equal js.login, actor.name
    assert_equal js.email, actor.email
    js.fullname = "sonic the hedgehog"
    assert_equal js.fullname, js.to_grit_actor.name
  end

  should "initially be pending" do
    u = create_user
    assert u.pending?
  end

  should "have many memberships" do
    groups(:team_thunderbird).add_member(users(:johan), Role.admin)
    assert_equal 2, users(:johan).memberships.count
  end

  should "have many groups through the memberships" do
    groups(:team_thunderbird).add_member(users(:johan), Role.admin)
    assert_equal Set.new([groups(:a_team), groups(:team_thunderbird)]), Set.new(users(:johan).groups)
  end

  should "have a to_param_with_prefix" do
    assert_equal "~#{users(:johan).to_param}", users(:johan).to_param_with_prefix
  end

  should "know who is a site admin" do
    assert !site_admin?(users(:mike))
    users(:mike).is_admin = true
    assert site_admin? users(:mike)
  end

  should "know if a user is a an admin of itself" do
    assert admin?(users(:mike), users(:mike))
    assert !admin?(users(:mike), users(:johan))
  end

  should "know if a user is a a committer of itself" do
    assert committer?(users(:mike), users(:mike))
    assert !committer?(users(:mike), users(:johan))
  end

  should "prepend http:// to the url if needed" do
    user = users(:johan)
    assert user.valid?
    user.url = "http://blah.com"
    assert user.valid?
    user.url = "blah.com"
    assert user.valid?
    assert_equal "http://blah.com", user.url
  end

  context "find_by_email_with_aliases" do
    should "find a user by primary email" do
      assert_equal users(:johan), User.find_by_email_with_aliases("johan@johansorensen.com")
    end

    should "find a user by email alias" do
      assert_equal users(:johan), User.find_by_email_with_aliases("johan@shortcut.no")
    end

    should "return nil when there is no user with that email or alias" do
      assert_nil User.find_by_email_with_aliases("wtf@fubar.no")
    end

    should "not include pending emails" do
      Email.create!(:user => users(:johan), :address => "foo@bar.com")
      assert_nil User.find_by_email_with_aliases("foo@bar.com")
    end
  end

  context "Messages" do
    setup do
      @message = messages(:johans_message_to_moe)
      @sender = users(:johan)
      @recipient = users(:moe)
    end

    should "know of its received messages" do
      assert @sender.sent_messages.include?(@message)
    end

    should "have an all_messages method that returns all messages to or from self" do
      assert @sender.all_messages.include?(@message)
      assert @recipient.all_messages.include?(@message)
      assert !users(:mike).all_messages.include?(@message)
    end

    should "know of its sent messages" do
      assert @recipient.received_messages.include?(@message)
    end

    should "keep track of the number of unread messages" do
      assert_equal(1, @recipient.received_messages.unread_count)
    end

    should "not include archived messages in the unread count" do
      msg = @recipient.received_messages.unread.first
      msg.archived_by(@recipient)
      msg.save!
      assert_equal(0, @recipient.received_messages.unread_count)
    end

    context "Top level messages" do
      setup do
        @sender = Factory.create(:user)
        @recipient = Factory.create(:user)
        @other_user = Factory.create(:user)
        @message = Message.create(:sender => @sender, :recipient => @recipient, :subject => "Hello", :body => "World")
      end

      should "include messages to self" do
        assert @recipient.top_level_messages.include?(@message)
        assert_equal @recipient, @message.recipient
        assert !@message.archived_by_recipient?
        assert @recipient.messages_in_inbox.include?(@message)
        @message.archived_by(@recipient)
        assert @message.save
        assert !@recipient.messages_in_inbox.include?(@message)
      end

      should "include messages from self with unread replies" do
        reply = @message.build_reply(:body => "Thx")
        assert reply.save
        assert @sender.top_level_messages.include?(@message)
        assert @sender.messages_in_inbox.include?(@message)
        @message.archived_by(@sender)
        assert @message.save
        assert @sender.messages_in_inbox.include?(@message)
      end

      should "not include messages from someone else with unread replies" do
        another_message = Message.create({
            :sender => @other_user,
            :recipient => @recipient,
            :subject => "Foo",
            :body => "Bar"
          })
        assert @recipient.messages_in_inbox.include?(another_message)
        another_reply = another_message.build_reply(:body => "Not for you")
        assert another_reply.save
        assert !@sender.top_level_messages.include?(another_message)
        assert !@sender.messages_in_inbox.include?(another_message)
      end
    end
  end

  context "Suspension" do
    setup do
      SshKey.any_instance.stubs(:valid_key_using_ssh_keygen?).returns(true)
      @user = users(:johan)
      @user.ssh_keys = [ssh_key]
    end

    should "set suspend timestamp and destroy ssh keys" do
      assert_equal nil, @user.suspended_at
      assert @user.ssh_keys.length > 0
      @user.suspend
      @user.save!
      assert !@user.suspended_at.nil?, "suspend timestamp should be set"
      assert_equal 0, @user.ssh_keys.length
    end

    should "be reversable (except for ssh keys)" do
      @user.suspended_at = Time.now
      @user.unsuspend
      @user.save!
      assert_equal nil, @user.suspended_at
    end
  end

  def ssh_key
    SshKey.new({:user_id => 1,
                 :key => "ssh-rsa bXljYWtkZHlpemltd21vY2NqdGJnaHN2bXFjdG9zbXplaGlpZnZ0a3VyZWFzc2dkanB4aXNxamxieGVib3l6Z3hmb2ZxZW15Y2FrZGR5aXppbXdtb2NjanRiZ2hzdm1xY3Rvc216ZWhpaWZ2dGt1cmVhc3NnZGpweGlzcWpsYnhlYm95emd4Zm9mcWU= foo@example.com"})
  end

  context "Avatars" do
    setup {@user = users(:johan)}

    should "generate an avatar path based on the user's login" do
      @user.avatar_file_name = "foo.png"
      assert_equal "/system/avatars/#{@user.login}/original/foo.png", @user.avatar.url
    end

    context "finding an avatar from an email" do
      should "return :nil when a user does not have an avatar" do
        assert_equal :nil, User.find_avatar_for_email(@user.email, :thumb)
      end

      should "return the user's avatar when the user has an avatar" do
        @user.update_attribute(:avatar_file_name, 'foo.png')
        Rails.cache.clear
        assert_equal @user.avatar.url(:thumb), User.find_avatar_for_email(@user.email, :thumb)
      end

      should "return :nil when an unknown email address is requested" do
        assert_equal :nil, User.find_avatar_for_email("noone@nowhere.com", :thumb)
      end
    end

    context "cache expirery of avatars" do
      should "expire the cache when the avatar is changed" do
        @user.update_attribute(:avatar_file_name, "foo.png")
        @user.update_attribute(:avatar_updated_at, 2.days.ago)

        assert_avatars_expired(@user) do
          @user.avatar = Paperclip::Attachment.new(:avatar, @user)
          @user.save
        end
      end

      should "expire the cache when the avatar is deleted" do
        @user.update_attribute(:avatar_file_name, "foo.png")
        @user.update_attribute(:avatar_updated_at, 2.days.ago)

        assert_avatars_expired(@user) do
          @user.avatar = nil
          @user.save
        end
      end

      should "expire the cache for all the styles" do
        @user.update_attribute(:avatar_file_name, "foo.png")
        @user.update_attribute(:avatar_updated_at, 2.days.ago)

        assert_avatars_expired(@user) do
          @user.avatar = nil
          @user.save
        end
      end

      should "expire the cache for all the alias emails as well" do
        @user.update_attribute(:avatar_file_name, "foo.png")
        @user.update_attribute(:avatar_updated_at, 2.days.ago)
        assert_equal 1, @user.email_aliases.count

        assert_avatars_expired(@user) do
          @user.avatar = nil
          @user.save
        end
      end
    end
  end


  context "Favorites" do
    setup do
      @user = users(:moe)
      @first_repo = repositories(:johans)
      @second_repo = repositories(:moes)
      @user.favorites.create!(:watchable => @first_repo)
    end

    should "have one favorite to begin with" do
      assert_equal 1, @user.favorites.size
    end

    should "include events for favorites" do
      branch_event = @first_repo.project.events.create!({
          :action => Action::CREATE_BRANCH,
          :target => @first_repo,
          :user => users(:mike),
          :body => "New branch",
          :data => "Integration",
        })
      comment_event = @first_repo.project.create_event(Action::COMMENT, @first_repo,
        users(:mike), 99, "Repository")
      Rails.cache.clear
      assert @user.paginated_events_in_watchlist(:page => 1).include?(branch_event)
      assert @user.paginated_events_in_watchlist(:page => 1).include?(comment_event)
    end

    should "not include events for non-favorite objects" do
      assert !@second_repo.watched_by?(@user)
      comment_event = @second_repo.project.create_event(Action::COMMENT, @second_repo,
        users(:mike), 99, "Repository")
      assert !@user.paginated_events_in_watchlist(:page => 1).include?(comment_event)
    end

    should "include events for favorited objects" do
      @user.favorites.create!(:watchable => @second_repo)
      @second_repo.reload
      comment_event = @second_repo.project.create_event(Action::COMMENT, @second_repo,
        users(:mike), 99, "Repository")
      assert @user.paginated_events_in_watchlist(:page => 1).include?(comment_event)
    end

    should "not include events for favorited objects if user is the event creator" do
      @user.favorites.create!(:watchable => @second_repo)
      @second_repo.reload
      comment_event = @second_repo.project.create_event(Action::COMMENT, @second_repo,
        @user, 99, "Repository")
      assert !@user.paginated_events_in_watchlist(:page => 1).include?(comment_event)
    end
  end

  def assert_avatars_expired(user, &block)
    user.avatar.styles.keys.each do |style|
      (user.email_aliases.map(&:address) << user.email).each do |email|
        cache_key = User.email_avatar_cache_key(email, style)
        Rails.cache.expects(:delete).with(cache_key)
      end
    end
    yield
  end

  context "most active users" do
    should "be retrieved as expected" do
      u1 = create_user(:login => "joe", :email => "joe@hepp.com")
      u2 = create_user(:login => "jane", :email => "jane@hepp.com")

      e1 = create_event(:action => Action::COMMIT, :user => u1, :body => "12")
      e2 = create_event(:action => Action::PUSH_SUMMARY, :user => u1, :body => "34")
      e3 = create_event(:action => Action::PUSH_SUMMARY, :user => u1, :body => "56")
      e4 = create_event(:action => Action::PUSH_SUMMARY, :user => u2, :body => "78")

      assert_not_nil User.most_active
      assert_equal 2, User.most_active.count
      assert_equal "2", User.most_active.first.event_count
      assert_equal "1", User.most_active.second.event_count
    end
  end

  context "user deletion" do
    should "be possible if user has no repos or projects" do
      u = User.new
      assert u.deletable?
    end

    should "not be possible if user has any current repos and/or projects" do
      assert !users(:johan).deletable?
    end
  end

  should "mass assign public_email" do
    user = create_user
    user.attributes = { :public_email => true }
    user.save
    assert user.public_email?

    user.attributes = { :public_email => false }
    user.save
    refute user.public_email?
  end

  protected
  def create_user(options = {})
    login = options.delete(:login) || "quire"
    password = options.delete(:password) || "quire"
    password_confirmation = options.delete(:password_confirmation) || "quire"
    u = User.new({ :email => "quire@example.com" }.merge(options))
    u.terms_of_use = "1"
    u.aasm_state = "pending"
    u.login = login
    u.password = password
    u.password_confirmation = password_confirmation
    u.save
    u
  end

  def create_event(options={})
    c = Event.new({ :target => repositories(:johans), :body => "blabla" }.merge(options))
    c.user = options[:user] || users(:johan)
    c.project = options[:project] || projects(:thunderbird)
    c.save!
    c
  end
end
