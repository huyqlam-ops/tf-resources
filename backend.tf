terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatemyapp123"   # đổi đúng tên bạn đã đặt được ở bước 2
    container_name        = "tfstate"
    key                    = "prod.terraform.tfstate"
    use_azuread_auth = true
  }
}