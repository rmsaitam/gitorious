# encoding: utf-8
#--
#   Copyright (C) 2012 Gitorious AS
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
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
require "test_helper"

class Admin::RepositoriesControllerTest < ActionController::TestCase
  should_enforce_ssl_for(:get, :index)
  should_enforce_ssl_for(:put, :recreate)

  def setup
    setup_ssl_from_config
  end

  context "Un-ready repositories" do
    should "deny access for regular users" do
      get :index
      assert_response :redirect
    end

    should "grant access to site admins" do
      login_as :johan
      get :index
      assert_response :success
    end

    should "re-post the creation message" do
      login_as :johan
      @repo = repositories(:johans)
      Repository.expects(:find).with("2").returns(@repo)
      put :recreate, :id => 2
      assert_response :redirect
    end
  end

  context "pagination" do
    setup { login_as :johan }
    should_scope_pagination_to(:index, Repository)
  end
end
