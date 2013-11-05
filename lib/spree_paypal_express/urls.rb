# encoding:utf-8
module SpreePaypalExpress
  module Urls
    extend ActiveSupport::Concern
    
    private
        
    def paypal_urls(order, payment_method, return_options = {}, cancel_options = {})
      host = request.host
      host = development_paypal_linkout_host(host) if Rails.env.development?
      port = request.port
      protocol = request.protocol
      r_opts = {:payment_method_id => payment_method.id, :host => host, :port => port, :protocol => protocol}
      r_opts.merge!(return_options)
      return_url = Spree::Core::Engine.routes.url_helpers.paypal_confirm_order_checkout_url(order, r_opts)
      c_opts = {:payment_method_id => payment_method.id, :host => host, :port => port, :protocol => protocol}
      c_opts.merge!(cancel_options)
      cancel_url = Spree::Core::Engine.routes.url_helpers.paypal_cancel_order_checkout_url(order, c_opts)
      [return_url, cancel_url]
    end
    
    def start_paypal_payment_url(order, payment_method, options = {})
      host = request.host
      host = development_paypal_linkout_host(host) if Rails.env.development?
      port = request.port
      protocol = request.protocol
      opts = {:payment_method_id => payment_method.id, :host => host, :port => port, :protocol => protocol}
      opts.merge!(options)
      Spree::Core::Engine.routes.url_helpers.paypal_payment_order_checkout_url(order, opts)
    end
    
    # To let users override the host for the urls handed to paypal, in case
    # you need to link to something other than "localhost" for testing.
    # Only used in development mode.
    def development_paypal_linkout_host(host)
      host
    end
    
  end
end
