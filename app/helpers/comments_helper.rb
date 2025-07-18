module CommentsHelper
  def value_for_comment_form(commentable, comment)
    commentable.is_a?(Tag) ? comment : [commentable, comment]
  end

  def title_for_comment_page(commentable)
    if commentable.commentable_name.blank?
      title = ""
    elsif commentable.is_a?(Tag)
      title = link_to_tag(commentable)
    else
      title = link_to(commentable.commentable_name, commentable)
    end
    (ts('Reading Comments on ') + title).html_safe
  end

  def link_to_comment_ultimate_parent(comment)
    ultimate = comment.ultimate_parent
    case ultimate.class.to_s
      when 'Work' then
        link_to ultimate.title, ultimate
      when 'Pseud' then
        link_to ultimate.name, ultimate
      when 'AdminPost' then
          link_to ultimate.title, ultimate
      else
        if ultimate.is_a?(Tag)
          link_to_tag(ultimate)
        else
          link_to 'Something Interesting', ultimate
        end
    end
  end

  def comment_link_with_commentable_name(comment)
    ultimate_parent = comment.ultimate_parent
    commentable_name = ultimate_parent&.commentable_name
    text = case ultimate_parent.class.to_s
           when "Work"
             t("comments_helper.comment_link_with_commentable_name.on_work_html", title: commentable_name)
           when "AdminPost"
             t("comments_helper.comment_link_with_commentable_name.on_admin_post_html", title: commentable_name)
           else
             if ultimate_parent.is_a?(Tag)
               t("comments_helper.comment_link_with_commentable_name.on_tag_html", name: commentable_name)
             else
               t("comments_helper.comment_link_with_commentable_name.on_unknown")
             end
           end
    link_to(text, comment_path(comment))
  end

  # return pseudname or name for comment
  def get_commenter_pseud_or_name(comment)
    if comment.pseud_id
      if comment.pseud.nil?
        ts("Account Deleted")
      elsif comment.pseud.user.official
        (link_to comment.pseud.byline, [comment.pseud.user, comment.pseud]) + content_tag(:span, " " + ts("(Official)"), class: "role")
      else
        link_to comment.pseud.byline, [comment.pseud.user, comment.pseud]
      end
    else
      content_tag(:span, comment.name) + content_tag(:span, " #{ts('(Guest)')}", class: "role")
    end
  end

  def chapter_description_link(comment)
    link_to t("comments_helper.chapter_link_html", position: comment.parent.position), work_chapter_path(comment.parent.work, comment.parent)
  end

  def image_safety_mode_cache_key(comment)
    "image-safety-mode" if comment.use_image_safety_mode?
  end

  ####
  ## Mar 4 2009 Enigel: the below shouldn't happen anymore, please test
  ####
  ## Note: there is a small but interesting bug here. If you first use javascript to open
  ## up the comments, the various url_for(:overwrite_params) arguments used below as the
  ## non-javascript fallbacks will end up with the wrong code, and so if you then turn
  ## off Javascript and try to use the links, you will get weirdo results. I think this
  ## is a bug we can live with for the moment; someone consistently browsing without
  ## javascript shouldn't have problems.
  ## -- Naomi, 9/2/2008
  ####

  #### Helpers for _commentable.html.erb ####

  # return link to show or hide comments
  def show_hide_comments_link(commentable, options={})
    options[:link_type] ||= "show"
    options[:show_count] ||= false

    commentable_id = commentable.is_a?(Tag) ?
                      :tag_id :
                      "#{commentable.class.to_s.underscore}_id".to_sym
    commentable_value = commentable.is_a?(Tag) ?
                          commentable.name :
                          commentable.id

    comment_count = commentable.count_visible_comments.to_s

    link_action = options[:link_type] == "hide" || params[:show_comments] ?
                    :hide_comments :
                    :show_comments

    link_text = ts("%{words} %{count}",
                  words: options[:link_type] == "hide" || params[:show_comments] ?
                              "Hide Comments" :
                              "Comments",
                  count: options[:show_count] ?
                              "(" +comment_count+ ")" :
                              "")

    link_to(
        link_text,
        url_for(controller: :comments,
                action: link_action,
                commentable_id => commentable_value,
                view_full_work: params[:view_full_work]),
        remote: true)
  end

  #### HELPERS FOR CHECKING WHICH BUTTONS/FORMS TO DISPLAY #####

  def can_reply_to_comment?(comment)
    admin_settings = AdminSetting.current

    return false if comment.unreviewed?
    return false if comment.iced?
    return false if comment.hidden_by_admin?
    return false if parent_disallows_comments?(comment)
    return false if comment_parent_hidden?(comment)
    return false if blocked_by_comment?(comment)
    return false if blocked_by?(comment.ultimate_parent)
    return false if logged_in_as_admin?

    return true unless guest?

    !(admin_settings.guest_comments_off? || comment.guest_replies_disallowed?)
  end

  def can_edit_comment?(comment)
    is_author_of?(comment) &&
      !comment.iced? &&
      comment.count_all_comments.zero? &&
      !comment_parent_hidden?(comment) &&
      !blocked_by_comment?(comment.commentable) &&
      !blocked_by?(comment.ultimate_parent)
  end

  # Only an admin with proper authorization can mark a spam comment ham.
  def can_mark_comment_ham?(comment)
    return unless comment.pseud.nil? && !comment.approved?

    policy(comment).can_mark_comment_spam?
  end

  # An admin with proper authorization or a creator of the comment's ultimate
  # parent (i.e. the work) can mark an approved comment as spam.
  def can_mark_comment_spam?(comment)
    return unless comment.pseud.nil? && comment.approved?

    policy(comment).can_mark_comment_spam? || is_author_of?(comment.ultimate_parent)
  end

  # Comments can be deleted by admins with proper authorization, their creator
  # (if the creator is a registered user), or the creator of the comment's
  # ultimate parent.
  def can_destroy_comment?(comment)
    policy(comment).can_destroy_comment? ||
      is_author_of?(comment) ||
      is_author_of?(comment.ultimate_parent)
  end

  # Comments on works can be frozen by admins with proper authorization or the
  # work creator.
  # Comments on tags can be frozen by admins with proper authorization.
  # Comments on admin posts can be frozen by any admin.
  def can_freeze_comment?(comment)
    policy(comment).can_freeze_comment? ||
      comment.ultimate_parent.is_a?(Work) &&
        is_author_of?(comment.ultimate_parent)
  end

  def can_hide_comment?(comment)
    policy(comment).can_hide_comment?
  end

  def can_see_hidden_comment?(comment)
    !comment.hidden_by_admin? ||
      is_author_of?(comment) ||
      can_hide_comment?(comment)
  end

  def comment_parent_hidden?(comment)
    parent = comment.ultimate_parent
    (parent.respond_to?(:hidden_by_admin) && parent.hidden_by_admin) ||
      (parent.respond_to?(:in_unrevealed_collection) && parent.in_unrevealed_collection)
  end

  def parent_disallows_comments?(comment)
    parent = comment.ultimate_parent
    return false unless parent.is_a?(Work) || parent.is_a?(AdminPost)

    parent.disable_all_comments? ||
      parent.disable_anon_comments? && !logged_in?
  end

  def can_review_comment?(comment)
    return false unless comment.unreviewed?

    is_author_of?(comment.ultimate_parent) || policy(comment).can_review_comment?
  end

  def can_review_all_comments?(commentable)
    commentable.is_a?(AdminPost) || is_author_of?(commentable)
  end

  #### HELPERS FOR REPLYING TO COMMENTS #####

  # return link to add new reply to a comment
  def add_comment_reply_link(comment)
    commentable_id = comment.ultimate_parent.is_a?(Tag) ?
                        :tag_id :
                        comment.parent.class.name.foreign_key.to_sym # :chapter_id, :admin_post_id etc.
    commentable_value = comment.ultimate_parent.is_a?(Tag) ?
                          comment.ultimate_parent.name :
                          comment.parent.id
    link_to(
      ts("Reply"),
      url_for(controller: :comments,
              action: :add_comment_reply,
              id: comment.id,
              comment_id: params[:comment_id],
              commentable_id => commentable_value,
              view_full_work: params[:view_full_work],
              page: params[:page]),
      remote: true)
  end

  # return link to cancel new reply to a comment
  def cancel_comment_reply_link(comment)
    commentable_id = comment.ultimate_parent.is_a?(Tag) ?
                        :tag_id :
                        comment.parent.class.name.foreign_key.to_sym
    commentable_value = comment.ultimate_parent.is_a?(Tag) ?
                          comment.ultimate_parent.name :
                          comment.parent.id
    link_to(
      ts("Cancel"),
      url_for(
        controller: :comments,
        action: :cancel_comment_reply,
        id: comment.id,
        comment_id: params[:comment_id],
        commentable_id => commentable_value,
        view_full_work: params[:view_full_work],
        page: params[:page]
      ),
      remote: true
    )
  end

  # canceling an edit
  def cancel_edit_comment_link(comment)
    link_to(ts("Cancel"),
            url_for(controller: :comments,
                    action: :cancel_comment_edit,
                    id: comment.id,
                    comment_id: params[:comment_id]),
            remote: true)
  end

  # return html link to edit comment
  def edit_comment_link(comment)
    link_to(ts("Edit"),
            url_for(controller: :comments,
                    action: :edit,
                    id: comment,
                    comment_id: params[:comment_id]),
            remote: true)
  end

  def do_cancel_delete_comment_link(comment)
    if params[:delete_comment_id] && params[:delete_comment_id] == comment.id.to_s
      cancel_delete_comment_link(comment)
    else
      delete_comment_link(comment)
    end
  end

  def freeze_comment_button(comment)
    if comment.iced?
      button_to ts("Unfreeze Thread"), unfreeze_comment_path(comment), method: :put
    else
      button_to ts("Freeze Thread"), freeze_comment_path(comment), method: :put
    end
  end

  def hide_comment_button(comment)
    if comment.hidden_by_admin?
      button_to ts("Make Comment Visible"), unhide_comment_path(comment), method: :put
    else
      button_to ts("Hide Comment"), hide_comment_path(comment), method: :put
    end
  end

  # Not a link or button, but included with them.
  def frozen_comment_indicator
    content_tag(:span, ts("Frozen"), class: "frozen current")
  end

  # return html link to delete comments
  def delete_comment_link(comment)
    link_to(
      ts("Delete"),
      url_for(controller: :comments,
              action: :delete_comment,
              id: comment,
              comment_id: params[:comment_id]),
      remote: true)
  end

  # return link to cancel new reply to a comment
  def cancel_delete_comment_link(comment)
    link_to(
      ts("Cancel"),
      url_for(controller: :comments,
              action: :cancel_comment_delete,
              id: comment,
              comment_id: params[:comment_id]),
      remote: true)
  end

  # return html link to mark/unmark comment as spam
  def tag_comment_as_spam_link(comment)
    if comment.approved
      link_to(ts("Spam"), reject_comment_path(comment), method: :put, data: { confirm: "Are you sure you want to mark this as spam?" })
    else
      link_to(ts("Not Spam"), approve_comment_path(comment), method: :put)
    end
  end

  # gets the css user-<id> class name for the comment
  def commenter_id_for_css_classes(comment)
    return if comment.pseud.nil?
    return if comment.by_anonymous_creator?
    return if comment.is_deleted
    return if comment.hidden_by_admin

    "user-#{comment.pseud.user_id}"
  end

  def css_classes_for_comment(comment)
    return if comment.nil?

    unavailable = "unavailable" if comment.hidden_by_admin
    unreviewed = "unreviewed" if comment.unreviewed?
    commenter = commenter_id_for_css_classes(comment)
    official = "official" if commenter && comment&.pseud&.user&.official
    guest = "guest" unless comment.pseud_id

    "#{unavailable} #{official} #{guest} #{unreviewed} comment group #{commenter}".squish
  end

  # find the parent of the commentable
  def find_parent(commentable)
    if commentable.respond_to?(:ultimate_parent)
      commentable.ultimate_parent
    elsif commentable.respond_to?(:work)
      commentable.work
    else
      commentable
    end
  end

  # if parent commentable is a work, determine if current user created it
  def current_user_is_work_creator(commentable)
    if logged_in?
      parent = find_parent(commentable)
      parent.is_a?(Work) && current_user.is_author_of?(parent)
    end
  end

  # if parent commentable is an anonymous work, determine if current user created it
  def current_user_is_anonymous_creator(commentable)
    if logged_in?
      parent = find_parent(commentable)
      parent.is_a?(Work) && parent.anonymous? && current_user.is_author_of?(parent)
    end
  end

  # determine if the parent has its comments set to moderated
  def comments_are_moderated(commentable)
    parent = find_parent(commentable)
    parent.respond_to?(:moderated_commenting_enabled) && parent.moderated_commenting_enabled?
  end

  def focused_on_comment(commentable)
    params[:add_comment_reply_id] && params[:add_comment_reply_id] == commentable.id.to_s
  end
end
