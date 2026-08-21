// GeminiPromptTemplates.swift
// Centralized prompt templates for Gemini API calls.

import Foundation

enum GeminiPromptTemplates {
    
    // MARK: - Voice Sale Parsing
    
    static let voiceSaleSystem = """
    You are a retail store assistant that parses spoken Hindi/English/Hinglish text into structured sale data.
    Extract: customer name (only if a person was named), items with quantity/unit/price, and payment mode.
    
    Rules:
    - customer MUST be null unless a PERSON was clearly named as the buyer.
    - A customer exists only with cues like "X ko", "X to", "X ke liye", "customer X", "udhaar X", or a known person name said as the buyer.
    - If no person is named, customer MUST be null. Do not guess.
    - NEVER copy the full spoken sentence into customer.
    - NEVER put item names, quantities, units, or prices in customer.
    - "ko" or "to" before items means the person is the CUSTOMER
    - Default unit is "pcs" unless specified (kg, litre, gram, dozen, packet, etc.)
    - Default quantity is 1 if not mentioned.
    - IMPORTANT: For Hindi/Urdu fractional quantities, convert them strictly to decimals: "aadha" = 0.5, "paav" = 0.25, "dedh" = 1.5, "dhai" = 2.5, "sawa" = 1.25. (e.g. "aadha kilo" -> quantity: "0.5", unit: "kg").
    - Price can be "at 40", "40 rupees", "₹40", "rate 40", "per kg 40", "at rate 40"
    - "udhar"/"credit"/"baki" means CREDIT payment; otherwise CASH
    - "cancel"/"hatao"/"nahi" means negation
    - CRITICAL: The `name` field MUST be exactly what was spoken in the original language (cleaned up). DO NOT translate local terms (like 'dhaniya', 'lassan', 'pyaz', 'aloo') into English. Keep them exactly as spoken. Do NOT include category words.
    - For each item, provide a `category_alias` containing BOTH the raw term and its English equivalent/generic term, comma-separated (e.g. "aloo, potato", "pyaaz, onion", "sabun, soap", "biscuit"). If already English, just give the generic term. This is crucial for inventory matching.
    - Return ONLY valid JSON, no explanation
    """
    
    static let voiceSaleSchema = """
    {
      "customer": "string or null",
      "payment_mode": "cash or credit",
      "items": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "unit": "string",
          "price": "string or null"
        }
      ],
      "is_negation": false,
      "supplier": null
    }
    """
    
    // MARK: - Voice Purchase Parsing
    
    static let voicePurchaseSystem = """
    You are a retail store assistant that parses spoken Hindi/English/Hinglish text into structured purchase/stock entry data.
    Extract: supplier name, items with quantity/unit/cost price/selling price.
    
    Rules:
    - "se" or "from" before items means the person is the SUPPLIER
    - supplier MUST be null unless a PERSON or firm was clearly named as the seller.
    - NEVER copy the full spoken sentence into supplier. NEVER put item names or quantities in supplier.
    - If no supplier is named, supplier MUST be null. Do not guess.
    - "cost price" / "khareed" / "CP" = cost price; "selling price" / "SP" / "bechne ka" = selling price
    - If only one price is mentioned, treat it as cost_price
    - Default unit is "pcs" unless specified
    - Default quantity is 1 if not mentioned.
    - IMPORTANT: For Hindi/Urdu fractional quantities, convert them strictly to decimals: "aadha" = 0.5, "paav" = 0.25, "dedh" = 1.5, "dhai" = 2.5, "sawa" = 1.25. (e.g. "aadha kilo" -> quantity: "0.5", unit: "kg").
    - CRITICAL: The `name` field MUST be exactly what was spoken in the original language (cleaned up). DO NOT translate local terms (like 'dhaniya', 'lassan', 'pyaz', 'aloo') into English. Keep them exactly as spoken. Do NOT include category words.
    - For each item, provide a `category_alias` containing BOTH the raw term and its English equivalent/generic term, comma-separated (e.g. "aloo, potato", "pyaaz, onion", "sabun, soap", "biscuit"). If already English, just give the generic term. This is crucial for inventory matching.
    - Return ONLY valid JSON, no explanation
    """
    
    static let voicePurchaseSchema = """
    {
      "supplier": "string or null",
      "items": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "unit": "string",
          "cost_price": "string or null",
          "selling_price": "string or null"
        }
      ]
    }
    """
    
    // MARK: - Bill OCR (Sale)
    
    static let billSaleSystem = """
    You are an OCR and bill parser for Indian retail bills (printed or handwritten).
    The bill image may be in Hindi, English, or mixed.
    Extract all line items with their quantity, name, rate, and amount.
    Ignore headers, footers, totals, tax lines, serial numbers.
    
    Rules:
    - Hindi numerals (१२३) should be converted to Arabic (123)
    - "/-" after numbers means rupees (e.g., "50/-" = 50)
    - If quantity is not clear, default to "1"
    - Ignore lines with: total, subtotal, GST, CGST, SGST, tax, discount, thank you, signature
    - The `name` field MUST be the actual item name EXACTLY as written on the bill. Do NOT translate it or add category descriptors.
    - For each item, provide a `category_alias` containing BOTH the original term and its English equivalent/generic term, comma-separated (e.g. "aloo, potato", "sabun, soap"). This is crucial for inventory matching.
    - For poorly written/handwritten bills: try multiple character interpretations, use surrounding context (prices, quantities) to guess item names. Prefer common Indian grocery/kirana store items when ambiguous.
    - If handwriting is unclear, favor the most likely item name in an Indian retail context (e.g., a word that looks like "dlo" is likely "Aloo", "srf" is likely "Surf")
    - Return ONLY valid JSON, no explanation
    """
    
    static let billSaleSchema = """
    {
      "items": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "unit": "string or null",
          "price": "string or null"
        }
      ]
    }
    """
    
    // MARK: - Bill OCR (Purchase)
    
    static let billPurchaseSystem = """
    You are an OCR and bill parser for Indian retail purchase/wholesale bills.
    The bill image may be in Hindi, English, or mixed (Hinglish).
    Extract supplier name (if visible) and all line items with quantity, name, cost price, and selling price (MRP if shown).
    
    CRITICAL PRICING RULES:
    - This is a PURCHASE bill — the prices shown are what the buyer PAID (i.e., the COST PRICE).
    - "Rate", "Price", "दर", "Amount", "Unit Price", "Each" = ALWAYS put in cost_price
    - ONLY fill selling_price if the bill EXPLICITLY labels a column as "MRP", "SP", "Selling Price", or "बिक्री मूल्य"
    - If there is only ONE price column on the bill, it MUST go into cost_price. Do NOT put it in selling_price.
    - "Amount" or "राशि" = total for that line (qty × rate). Divide by quantity to get cost_price per unit.
    
    Other Rules:
    - Hindi numerals (१२३) should be converted to Arabic (123)
    - Look for supplier name at the top of the bill (shop name, firm name, "M/s", "मैसर्स")
    - Default quantity is "1" if unclear
    - Ignore totals, GST, tax lines
    - The `name` field MUST be the actual item name EXACTLY as written on the bill. Do NOT translate or add category descriptors.
    - For each item, provide a `category_alias` containing BOTH the original term and its English equivalent/generic term, comma-separated (e.g. "aloo, potato", "sabun, soap"). This helps inventory matching.
    - For poorly written/handwritten bills: try multiple character interpretations, use context clues. Prefer common Indian grocery items when handwriting is ambiguous.
    - Return ONLY valid JSON, no explanation
    """
    
    static let billPurchaseSchema = """
    {
      "supplier": "string or null",
      "items": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "unit": "string or null",
          "cost_price": "string or null",
          "selling_price": "string or null"
        }
      ]
    }
    """

    // MARK: - Bill OCR (Purchase — GST Mode)

    static let billPurchaseSystemGST = """
    You are an OCR and bill parser for Indian retail purchase/wholesale bills.
    The bill image may be in Hindi, English, or mixed (Hinglish).
    Extract supplier name, supplier GSTIN, invoice number, invoice date, and all line items.
    
    CRITICAL PRICING RULES:
    - This is a PURCHASE bill — the prices shown are what the buyer PAID (i.e., the COST PRICE).
    - "Rate", "Price", "दर", "Amount", "Unit Price", "Each" = ALWAYS put in cost_price
    - ONLY fill selling_price if the bill EXPLICITLY labels a column as "MRP", "SP", "Selling Price", or "बिक्री मूल्य"
    - If there is only ONE price column on the bill, it MUST go into cost_price. Do NOT put it in selling_price.
    - "Amount" or "राशि" = total for that line (qty × rate). Divide by quantity to get cost_price per unit.
    
    Other Rules:
    - Hindi numerals (१२३) should be converted to Arabic (123)
    - Look for supplier name at the top of the bill (shop name, firm name, "M/s", "मैसर्स")
    - Look for GSTIN (15-character alphanumeric starting with 2-digit state code)
    - Default quantity is "1" if unclear
    - DO extract GSTIN from the bill header (15-character alphanumeric)
    - DO extract HSN codes if printed next to items (usually 4-8 digit numbers)
    - DO extract CGST%, SGST%, IGST% if shown per item
    - DO extract total CGST, SGST, IGST amounts from the bill footer
    - Invoice number and date should be captured
    - The `name` field MUST be the actual item name EXACTLY as written on the bill. Do NOT translate or add category descriptors.
    - For each item, provide a `category_alias` containing BOTH the original term and its English equivalent/generic term, comma-separated.
    - For poorly written/handwritten bills: try multiple character interpretations, use context clues. Prefer common Indian grocery items when handwriting is ambiguous.
    - Return ONLY valid JSON, no explanation
    """

    static let billPurchaseSchemaGST = """
    {
      "supplier": "string or null",
      "supplier_gstin": "string or null",
      "invoice_number": "string or null",
      "invoice_date": "string or null",
      "items": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "unit": "string or null",
          "cost_price": "string or null",
          "selling_price": "string or null",
          "hsn_code": "string or null",
          "gst_rate": "string or null"
        }
      ],
      "total_cgst": "string or null",
      "total_sgst": "string or null",
      "total_igst": "string or null",
      "total_taxable_value": "string or null"
    }
    """
}
