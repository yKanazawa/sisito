module ApplicationHelper
  def mail_link(bounce_mail, options = {target: '_blank'})
    if bounce_mail.link
      link_to(bounce_mail.recipient, bounce_mail.link, options)
    else
      bounce_mail.recipient
    end
  end

  def bounce_over?(whitelist_mail_created_at, bounce_mail_timestamp)
    buf = Rails.application.config.sisito.dig(:bounce_over, :buffer) || 0
    whitelist_mail_created_at.present? and
    bounce_mail_timestamp.present? and
    bounce_mail_timestamp > (whitelist_mail_created_at + buf)
  end

  def blacklisted_label?(bounce_mail)
    if filter = Rails.application.config.sisito[:blacklisted_label_filter]
      not bounce_mail.whitelisted and filter.call(bounce_mail)
    else
      false
    end
  end

  def current_top_path?(path)
    path.split('/')[1] ==    url_for(request.params).split('/')[1]
  end
end
