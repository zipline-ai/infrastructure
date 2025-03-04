variable "region" {
  default = "us-west-1"
}

variable "customer_accounts" {

  default = {
    canary = "345594603419"
    dev    = "345594603419"
    plaid  = "354918366284"

  }
}
