# encoding:utf-8
module SpreePaypalExpress
  module Urls
    extend ActiveSupport::Concern
    
    private
        
    def paypal_urls(order, payment_method)
      host = request.host
      host = "192.168.2.112"
      port = request.port
      return_url = Spree::Core::Engine.routes.url_helpers.paypal_confirm_order_checkout_url(order, :payment_method_id => payment_method.id, :host => host, :port => port)
      cancel_url = Spree::Core::Engine.routes.url_helpers.paypal_cancel_order_checkout_url(order, :payment_method_id => payment_method.id, :host => host, :port => port)
      [return_url, cancel_url]
    end
    
  end
end
