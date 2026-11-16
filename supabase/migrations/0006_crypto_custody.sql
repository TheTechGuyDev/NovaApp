-- =====================================================================
-- Phase 5: custodial crypto wallets (testnet)
-- Master seeds are AES-GCM encrypted by the Edge Function before storage;
-- the database never sees plaintext keys. No client can read these tables.
-- =====================================================================

create table public.custody_master (
  chain text primary key,                 -- bitcoin, ethereum, bsc, solana, tron
  xpub text,
  encrypted_secret text not null,         -- mnemonic (HD chains) or private key (solana hot wallet)
  hot_address text not null,              -- index 0: withdrawals are sent from here
  next_index int not null default 1,
  created_at timestamptz not null default now()
);

-- Per-user keys for chains without HD derivation in Tatum (Solana).
create table public.custody_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  chain text not null,
  address text not null unique,
  encrypted_private_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, chain)
);

alter table public.custody_master enable row level security;
alter table public.custody_keys enable row level security;
-- (no policies: service role only)

create or replace function public.next_custody_index(_chain text)
returns int language sql security definer set search_path = public as $$
  update custody_master set next_index = next_index + 1 where chain = _chain returning next_index - 1
$$;
revoke all on function public.next_custody_index(text) from public, anon, authenticated;
grant execute on function public.next_custody_index(text) to service_role;

-- Deposit tracking.
alter table public.deposit_addresses add column if not exists last_balance numeric(38,18) not null default 0;
alter table public.deposit_addresses add column if not exists last_synced_at timestamptz;
create unique index if not exists uq_deposit_tx
  on public.transactions (network_id, tx_hash, user_id) where type = 'deposit' and tx_hash is not null;

-- Testnet routes. Token networks need a testnet contract to track deposits.
alter table public.networks add column if not exists tatum_chain text;
alter table public.networks add column if not exists explorer_tx_url text;
alter table public.networks add column if not exists explorer_address_url text;

update public.networks set chain = 'bitcoin', tatum_chain = 'bitcoin',
  explorer_tx_url = 'https://mempool.space/testnet/tx/{hash}',
  explorer_address_url = 'https://mempool.space/testnet/address/{address}' where id = 'BTC_BTC';
update public.networks set tatum_chain = 'ethereum-sepolia',
  explorer_tx_url = 'https://sepolia.etherscan.io/tx/{hash}',
  explorer_address_url = 'https://sepolia.etherscan.io/address/{address}' where chain = 'ethereum';
update public.networks set tatum_chain = 'bsc-testnet',
  explorer_tx_url = 'https://testnet.bscscan.com/tx/{hash}',
  explorer_address_url = 'https://testnet.bscscan.com/address/{address}' where chain = 'bsc';
update public.networks set tatum_chain = 'solana-devnet',
  explorer_tx_url = 'https://explorer.solana.com/tx/{hash}?cluster=devnet',
  explorer_address_url = 'https://explorer.solana.com/address/{address}?cluster=devnet' where chain = 'solana';
update public.networks set tatum_chain = 'tron-testnet',
  explorer_tx_url = 'https://nile.tronscan.org/#/transaction/{hash}',
  explorer_address_url = 'https://nile.tronscan.org/#/address/{address}' where chain = 'tron';

-- Circle's official Sepolia USDC; other testnet tokens have no canonical contract.
update public.networks set contract_address = '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' where id = 'USDC_ERC20';
update public.networks set deposits_enabled = false, withdrawals_enabled = false
  where id in ('USDT_ERC20', 'USDT_TRC20', 'USDT_BEP20', 'USDC_SOL');

-- Testnet-friendly minimums and fees.
update public.networks set min_withdrawal = 0.0001, withdrawal_fee = 0.00001, confirmations_required = 1 where id = 'BTC_BTC';
update public.networks set min_withdrawal = 0.001, withdrawal_fee = 0.0002, confirmations_required = 3 where id = 'ETH_ERC20';
update public.networks set min_withdrawal = 0.001, withdrawal_fee = 0.0002, confirmations_required = 3 where id = 'BNB_BEP20';
update public.networks set min_withdrawal = 0.01, withdrawal_fee = 0.0001, confirmations_required = 1 where id = 'SOL_SOL';
update public.networks set min_withdrawal = 1, withdrawal_fee = 0.5, confirmations_required = 3 where id = 'USDC_ERC20';

-- Look up a NOVA user for crypto sends (same as Naira, reused).
