// GeminiPromptTemplates.swift
// Centralized prompt templates for Gemini API calls.

import Foundation

enum GeminiPromptTemplates {
    
    // MARK: - Voice Sale Parsing
    
    static let voiceSaleSystem = """
    You are a retail store assistant that parses spoken Hindi/English/Hinglish text into structured sale data.
    Extract: customer name, items with quantity/unit/price, and payment mode.
    
    Rules:
    - "ko" or "to" before items means the person is the CUSTOMER
    - Default unit is "pcs" unless specified (kg, litre, gram, dozen, packet, etc.)
    - Default quantity is 1 if not mentioned
    - Price can be "at 40", "40 rupees", "₹40", "rate 40", "per kg 40", "at rate 40"
    - "udhar"/"credit"/"baki" means CREDIT payment; otherwise CASH
    - "cancel"/"hatao"/"nahi" means negation
    - The `name` field MUST be exactly what was spoken/written (cleaned up). Do NOT translate it to English (e.g. if they say 'Aloo', keep it 'Aloo', not 'Potato'). Do NOT include category words.
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
    - "cost price" / "khareed" / "CP" = cost price; "selling price" / "SP" / "bechne ka" = selling price
    - If only one price is mentioned, treat it as cost_price
    - Default unit is "pcs" unless specified
    - Default quantity is 1 if not mentioned
    - The `name` field MUST be exactly what was spoken/written (cleaned up). Do NOT translate it to English (e.g. keep 'Aloo', don't write 'Potato'). Do NOT include category words.
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
    
    Rules:
    - Hindi numerals (१२३) should be converted to Arabic (123)
    - Look for supplier name at the top of the bill (shop name, firm name, "M/s", "मैसर्स")
    - "Rate" or "दर" = cost price per unit
    - "MRP" or "SP" = selling price
    - "Amount" or "राशि" = total for that line (qty × rate)
    - If only one price column exists, treat it as cost_price
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
    
    Rules:
    - Hindi numerals (१२३) should be converted to Arabic (123)
    - Look for supplier name at the top of the bill (shop name, firm name, "M/s", "मैसर्स")
    - Look for GSTIN (15-character alphanumeric starting with 2-digit state code)
    - "Rate" or "दर" = cost price per unit
    - "MRP" or "SP" = selling price
    - "Amount" or "राशि" = total for that line (qty × rate)
    - If only one price column exists, treat it as cost_price
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
    
    // MARK: - Object/Product Identification
    
    static let objectDetectionSystem = """
    You are a product identification assistant for an Indian retail/kirana store.
    Look at the image and identify EVERY SINGLE VISIBLE RETAIL PRODUCT.
    Do NOT group different products together. You MUST list each visually distinct product as a separate item in the array.
    For each product, estimate the count of visible units.
    
    Rules:
    - Identify ALL products you can see, no matter how small or in the background.
    - Return common product names (e.g., "Parle-G", "Maggi Noodles", "Surf Excel")
    - If brand is not visible, describe the product generically (e.g., "Rice packet", "Dal bag")
    - The `name` should be ONLY the product name (with brand if visible). Do NOT add generic category words here.
    - Count visible units of each product
    - If price label is visible on the product, include it
    - Provide a `category_alias` containing BOTH the original term and its English equivalent/generic term, comma-separated (e.g. "parle-g, biscuit", "aloo, potato", "surf, detergent").
    - Return ONLY valid JSON, no explanation
    """
    
    static let objectDetectionSchema = """
    {
      "products": [
        {
          "name": "string",
          "category_alias": "string or null",
          "quantity": "string",
          "price": "string or null"
        }
      ]
    }
    """
}
