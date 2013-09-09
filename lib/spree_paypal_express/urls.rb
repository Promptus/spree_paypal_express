# encoding:utf-8
module SpreePaypalExpress
  module Urls
    extend ActiveSupport::Concern
    
    private
        
    def paypal_urls(order, payment_method)
      host = request.host
      host = development_paypal_linkout_host(host) if Rails.env.development?
      port = request.port
      return_url = Spree::Core::Engine.routes.url_helpers.paypal_confirm_order_checkout_url(order, :payment_method_id => payment_method.id, :host => host, :port => port)
      cancel_url = Spree::Core::Engine.routes.url_helpers.paypal_cancel_order_checkout_url(order, :payment_method_id => payment_method.id, :host => host, :port => port)
      [return_url, cancel_url]
    end
    
    # To let users override the host for the urls handed to paypal, in case
    # you need to link to something other than "localhost" for testing.
    # Only used in development mode.
    def development_paypal_linkout_host(host)
      host
    end
    
  end
end
