module Spree
  CheckoutController.class_eval do
    
    include SpreePaypalExpress::ParameterMethods
    include SpreePaypalExpress::Urls
    include SpreePaypalExpress::ResultRendering

    # this starts a payment process with paypal and redirects the user to it
    def paypal_payment
      load_order
      unless @order.checkout_payment
        @order.payments.create!(
          :payment_method_id => payment_method.id,
          :amount => @order.total
        )
      end
      payment = @order.checkout_payment
      return_url, cancel_url = *paypal_urls(@order, payment_method, paypal_return_url_options, paypal_cancel_url_options)
      # TODO: the from_api? call doesn't really belong in this project
      if redirect_url = payment_method.start_payment!(@order, return_url, cancel_url)
        redirect_to redirect_url
        payment.started_processing!
      else
        payment.started_processing! if payment.checkout?
        payment.failure!
        failed_payment_callback(payment, payment_method.ppx_response)
        render_error(payment_method.ppx_response)
      end
    rescue ActiveMerchant::ConnectionError, SpreePaypalExpress::PaymentSetupFailedError
      failed_payment_callback(payment)
      render_error(I18n.t(:unable_to_connect_to_gateway))
    end

    def paypal_confirm
      load_order
      @order.reload # Needed here so that the order total is consistent with other checkout actions
      payment = nil
      ppx_details, payment = *get_payment_from_details(params[:token])
      payer_id = ppx_details.params["payer_id"]
      if ppx_details.success? and payer_id == params[:PayerID]
        paypal_account = find_or_create_paypal_account(ppx_details)
        return_url, cancel_url = *paypal_urls(@order, payment_method)
        opts = { :token => params[:token], :payer_id => payer_id }.merge all_opts(@order, payment, 'payment', return_url, cancel_url)
        amount = (@order.total*100).to_i
        record_log payment, {:amount => amount, :opts => opts, :method => :purchase}
        ppx_purchase_response = paypal_gateway.purchase(amount, opts)
        Rails.logger.debug "Paypal purchase response:"
        Rails.logger.debug ppx_purchase_response.to_yaml
        record_log payment, ppx_purchase_response
        payment.source = paypal_account
        payment.source_type = 'Spree::PaypalAccount'
        payment.response_code = ppx_purchase_response.authorization
        payment.avs_response = ppx_purchase_response.avs_result["code"]
        payment.save!
        
        paid_amount = BigDecimal(ppx_purchase_response.params["gross_amount"])

        if ppx_purchase_response.success?
          if paid_amount == payment.amount
            case ppx_purchase_response.params["payment_status"]
            when "Completed"
              payment.complete!
              @order.next
              render_success
            when "Pending"
              payment.failure!
              failed_payment_callback(payment, ppx_purchase_response)
              render_error("Payment is pending, please contact support.")
            else
              payment.failure!
              failed_payment_callback(payment, ppx_purchase_response)
              render_error(ppx_purchase_response)
            end
          else
            payment.failure!
            failed_payment_callback(payment, ppx_purchase_response)
            render_error("Payment has succeeded, but balance was not sufficient.")
          end
        else
          payment.failure!
          failed_payment_callback(payment, ppx_purchase_response)
          render_error(ppx_purchase_response)
        end
      else
        payment.failure!
        render_error(ppx_details)
      end
    rescue ActiveMerchant::ConnectionError
      if payment
        failed_payment_callback(payment)
        payment.failure!
      end
      render_error(I18n.t(:unable_to_connect_to_gateway))
    end
    
    def paypal_cancel
      load_order
      _, payment = *get_payment_from_details(params[:token])
      payment.cancel!
      render_cancel(I18n.t(:payment_cancelled))
    end
    
    private

    # to be overriden
    def failed_payment_callback(payment, last_response = nil)
      msg = "Failed payment: #{payment.inspect}"
      Rails.logger.info msg
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
      
      payment = Spree::Payment.find(ppx_details.params["PaymentDetails"]["InvoiceID"])
      
      record_log payment, ppx_details
      
      [ppx_details, payment]
    end
    
    def paypal_return_url_options
      {}
    end
    
    def paypal_cancel_url_options
      {}
    end

  end
end
