-- Phase 8: new transaction types (must commit before use).
alter type public.txn_type add value if not exists 'savings_deposit';
alter type public.txn_type add value if not exists 'savings_withdrawal';
alter type public.txn_type add value if not exists 'interest';
alter type public.txn_type add value if not exists 'card_payment';
alter type public.txn_type add value if not exists 'card_funding';
