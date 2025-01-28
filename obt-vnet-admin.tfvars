admin = {
  name  = "AttilaVamos"
  email = "attila.vamos@lexisnexisrisk.com"
}

metadata = {
  project             = "hpccdemo"
  product_name        = "vnet"
  business_unit       = "commercial"
  environment         = "sandbox"
  market              = "us"
  product_group       = "contoso"
  resource_group_type = "app"
  sre_team            = "hpccplatform"
  subscription_type   = "dev"
}

tags = { "justification" = "testing"
         "owner"         = "AttilaVamos"
         "owner_email"   = "attila.vamos@lexisnexisrisk.com"
       }

resource_group = {
  unique_name = true
  location    = "eastus"
}
