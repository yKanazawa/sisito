class WhitelistMailsController < ApplicationController
  before_action :set_whitelist_mail, only: [:destroy, :show]

  unless Rails.application.config.sisito.fetch(:authz).fetch(:show_whitelist)
    before_action :authenticate, except: [:register, :deregister]
  end

  def index
    @whitelist_mails = WhitelistMail.select('whitelist_mails.*', 'MAX(bounce_mails.timestamp) AS max_bounce_mail_timestamp')
                                .joins('LEFT JOIN bounce_mails' +
                                       '  ON whitelist_mails.recipient = bounce_mails.recipient ' +
                                       ' AND whitelist_mails.senderdomain = bounce_mails.senderdomain')
                                .group(:recipient, :senderdomain)
                                .order(created_at: :desc)
                                .page(params[:page])
  end

  def new
    @whitelist_mail = WhitelistMail.new
  end

  def create
    @whitelist_mail = WhitelistMail.new(whitelist_mail_params)

    if @whitelist_mail.save
      whitelisted_callback(@whitelist_mail)
      redirect_to whitelist_mails_path, notice: 'Whitelist mail was successfully created.'
    else
      render :new
    end
  end

  def show
    bounce_mail_id = BounceMail.where(recipient: @whitelist_mail.recipient).maximum(:id)
    @bounce_mail = BounceMail.find(bounce_mail_id)

    @history = BounceMail.where(recipient: @bounce_mail.recipient, senderdomain: @bounce_mail.senderdomain)
                         .order(timestamp: :desc)
                         .page(params[:page])
  end

  def register
    whitelist_mail = WhitelistMail.new(whitelist_mail_params)

    unless WhitelistMail.exists?(recipient: whitelist_mail.recipient, senderdomain: whitelist_mail.senderdomain)
      whitelist_mail.save!
      whitelisted_callback(whitelist_mail)
    end

    if params[:return_to]
      redirect_to params[:return_to]
    else
      redirect_to whitelist_mails_path
    end
  end

  def deregister
    whitelist_mail = WhitelistMail.where(recipient: whitelist_mail_params[:recipient], senderdomain: whitelist_mail_params[:senderdomain]).take

    if whitelist_mail
      whitelist_mail.destroy!
      unwhitelisted_callback(whitelist_mail)
    end

    if params[:return_to]
      redirect_to params[:return_to]
    else
      redirect_to whitelist_mails_path
    end
  end

  def destroy
    if @whitelist_mail.destroy
      unwhitelisted_callback(@whitelist_mail)
    end

    redirect_to whitelist_mails_path, notice: 'Whitelist mail was successfully destroyed.'
  end

  private

  def set_whitelist_mail
    @whitelist_mail = WhitelistMail.find(params[:id])
  end

  def whitelist_mail_params
    params.require(:whitelist_mail).permit(:recipient, :senderdomain)
  end

  def authenticate
    sisito_config = Rails.application.config.sisito

    authenticate_or_request_with_http_digest do |username|
      if username == sisito_config.fetch(:admin).fetch(:username)
        sisito_config.fetch(:admin).fetch(:password)
      end
    end
  end

  def whitelisted_callback(whitelist_mail)
    callback = Rails.application.config.sisito.fetch(:whitelist_callback, {})[:whitelisted]
    execute_callback0(callback, whitelist_mail) if callback
  end

  def unwhitelisted_callback(whitelist_mail)
    callback = Rails.application.config.sisito.fetch(:whitelist_callback, {})[:unwhitelisted]
    execute_callback0(callback, whitelist_mail) if callback
  end

  def execute_callback0(callback, whitelist_mail)
    recipients = [whitelist_mail.recipient, *whitelist_mail.bounce_mails.map(&:alias)].uniq
    cmd = [callback, *recipients].shelljoin
    Rails.logger.info "Execute #{cmd}"

    out, err, status = Open3.capture3(cmd)
    Rails.logger.info "  #{cmd}: stdout: #{out}" unless out.empty?
    Rails.logger.warn "  #{cmd}: stderr: #{err}" unless err.empty?

    unless status.success?
      Rails.logger.error "  #{cmd}: execution failed: exitstatus=#{status.exitstatus}"
    end
  end
end
