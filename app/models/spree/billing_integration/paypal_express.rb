class Spree::BillingIntegration::PaypalExpress < Spree::BillingIntegration::PaypalExpressBase
  
  include SpreePaypalExpress::ParameterMethods
  def payment_method
    self # for compat with ParameterMethods used in controller
  end
  
  preference :currency, :string, :default => 'USD'
  
  attr_accessor :ppx_response
  
  def linkout_url(payment, mobile, options)
    if redirect_url = start_payment!(payment.order, options[:return_url], options[:cancel_url], :mobile => mobile)
      redirect_url
    else
      nil
    end
  end
  
  # moved from CheckoutController(Decorator)#paypal_payment
  def start_payment!(order, return_url, cancel_url, redirect_opts = {})
    order.reload
    payment = order.checkout_payment
    opts = all_opts(order, payment, 'payment', return_url, cancel_url)
    opts.merge!(address_options(order))
    
    Rails.logger.debug "Paypal purchase setup options:"
    Rails.logger.debug opts
    @ppx_response = provider.setup_purchase(opts[:money], opts)
    Rails.logger.debug "Paypal purchase setup response:"
    Rails.logger.debug @ppx_response.to_yaml
    payment.started_processing!
    
    if @ppx_response.success?
      provider.redirect_url_for(@ppx_response.token, {:review => preferred_review}.merge(redirect_opts))
    else
      false
    end
  end
end
