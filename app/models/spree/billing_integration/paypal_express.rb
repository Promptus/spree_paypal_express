class Spree::BillingIntegration::PaypalExpress < Spree::BillingIntegration::PaypalExpressBase
  
  include SpreePaypalExpress::ParameterMethods
  def payment_method
    self # for compat with ParameterMethods used in controller
  end
  
  preference :currency, :string, :default => 'USD'
  
  attr_accessor :ppx_response
  
  # moved from CheckoutController(Decorator)#paypal_payment
  def start_payment!(order, return_url, cancel_url, redirect_opts = {})
    order.reload
    payment = order.checkout_payment
    opts = all_opts(order, payment, 'payment', return_url, cancel_url)
    opts.merge!(address_options(order))
    
    Rails.logger.debug "Paypal purchase setup options:"
    Rails.logger.debug opts
    record_log payment, {:money => opts[:money], :opts => opts, :method => :setup_purchase}
    @ppx_response = provider.setup_purchase(opts[:money], opts)
    Rails.logger.debug "Paypal purchase setup response:"
    Rails.logger.debug @ppx_response.to_yaml
    record_log payment, @ppx_response
    payment.started_processing!
    
    if @ppx_response.success?
      provider.redirect_url_for(@ppx_response.token, {:review => preferred_review}.merge(redirect_opts))
    else
      payment.failure!
      raise SpreePaypalExpress::PaymentSetupFailedError
    end
  rescue ActiveMerchant::ConnectionError
    raise SpreePaypalExpress::PaymentSetupFailedError
  end
end
