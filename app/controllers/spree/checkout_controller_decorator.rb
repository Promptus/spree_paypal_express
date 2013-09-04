module Spree
  CheckoutController.class_eval do
    
    include SpreePaypalExpress::ParameterMethods
    include SpreePaypalExpress::Urls
    include SpreePaypalExpress::ResultRendering
    
    before_filter :redirect_to_paypal_express_form_if_needed, :only => [:update]

    # this starts a payment process with paypal and redirects the user to it
    def paypal_payment
      load_order
      unless @order.checkout_payment
        @order.payments.create!(
          :payment_method_id => payment_method.id,
          :amount => @order.total
        )
      end
      return_url, cancel_url = *paypal_urls(@order, payment_method)
      if redirect_url = payment_method.start_payment!(@order, return_url, cancel_url)
        redirect_to redirect_url
      else
        render_error(payment_method.ppx_response)
      end
    rescue ActiveMerchant::ConnectionError, SpreePaypalExpress::PaymentSetupFailedError
      render_error(I18n.t(:unable_to_connect_to_gateway))
    end

    def paypal_confirm
      load_order
      payment = nil
      ppx_details, payment = *get_payment_from_details(params[:token])
      payer_id = ppx_details.params["payer_id"]
      if ppx_details.success? and payer_id == params[:PayerID]
        paypal_account = find_or_create_paypal_account(ppx_details)
        return_url, cancel_url = *paypal_urls(@order, payment_method)
        opts = { :token => params[:token], :payer_id => payer_id }.merge all_opts(@order, payment, 'payment', return_url, cancel_url)
        ppx_purchase_response = paypal_gateway.purchase((@order.total*100).to_i, opts)
        Rails.logger.debug "Paypal purchase response:"
        Rails.logger.debug ppx_purchase_response.to_yaml
        record_log payment, ppx_purchase_response
        payment.source = paypal_account
        payment.source_type = 'Spree::PaypalAccount'
        payment.response_code = ppx_purchase_response.authorization
        payment.avs_response = ppx_purchase_response.avs_result["code"]
        payment.save!
        
        paid_amount = Float(ppx_purchase_response.params["gross_amount"])

        if ppx_purchase_response.success? and paid_amount == payment.amount
          case ppx_purchase_response.params["payment_status"]
          when "Completed"
            payment.complete!
            @order.next
            render_success
          else
            payment.failure!
            render_error(ppx_purchase_response)
          end
        else
          payment.failure!
          render_error(ppx_purchase_response)
        end
      else
        payment.failure!
        render_error(ppx_details)
      end
    rescue ActiveMerchant::ConnectionError
      payment.failure! if payment
      render_error(I18n.t(:unable_to_connect_to_gateway))
    end
    
    def paypal_cancel
      load_order
      _, payment = *get_payment_from_details(params[:token])
      payment.cancel!
      render_cancel(I18n.t(:payment_cancelled))
    end
    
    private

    def redirect_to_paypal_express_form_if_needed
      return unless (params[:state] == "payment")
      return unless params[:order][:payments_attributes]

      payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      return unless payment_method.kind_of?(Spree::BillingIntegration::PaypalExpress) || payment_method.kind_of?(Spree::BillingIntegration::PaypalExpressUk)

      update_params = object_params.dup
      update_params.delete(:payments_attributes)
      if @order.update_attributes(update_params)
        fire_event('spree.checkout.update')
        render :edit and return unless apply_coupon_code
      end

      load_order
      if @order.errors.empty?
        redirect_to(paypal_payment_order_checkout_url(@order, :payment_method_id => payment_method.id)) and return
      else
        render :edit and return
      end
    end

    def gateway_error(response)
      if response.is_a? ActiveMerchant::Billing::Response
        text = response.params['message'] ||
               response.params['response_reason_text'] ||
               response.message
      else
        text = response.to_s
      end

      if I18n.locale == :en
        text = "#{I18n.t('gateway_error')}: #{text}"
      else
        # Parameterize text for i18n key
        text = text.parameterize(sep = '_')
        text = "#{I18n.t('gateway_error')}: #{I18n.t(text)}"
      end
      logger.error text
      flash[:error] = text
    end

    def payment_method
      @payment_method ||= Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def paypal_gateway
      payment_method.provider
    end
    
    def find_or_create_paypal_account(ppx_details)
      email =   ppx_details.params["payer"]
      id =      ppx_details.params["payer_id"]
      country = ppx_details.params["payer_country"]
      status =  ppx_details.params["payer_status"]
      
      attrs = {
        :email => email,
        :payer_id => id,
        :payer_country => country,
        :payer_status => status,
      }
      
      paypal_account = Spree::PaypalAccount.where(attrs).first
      unless paypal_account
        Rails.logger.debug "Creating new paypal account with #{attrs.inspect}"
        paypal_account = Spree::PaypalAccount.create(attrs)
      end
      paypal_account
    end
    
    def get_payment_from_details(token)
      gateway = paypal_gateway

      ppx_details = gateway.details_for(token)
      
      Rails.logger.debug "Paypal details response:"
      Rails.logger.debug ppx_details
      
      payment = Spree::Payment.find(ppx_details.params["PaymentDetails"]["Custom"])
      
      [ppx_details, payment]
    end

  end
end
