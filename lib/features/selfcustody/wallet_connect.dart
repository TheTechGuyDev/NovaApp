import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../../core/config.dart';

/// Connects an external wallet (MetaMask, Trust, Phantom, Coinbase...) through
/// Reown / WalletConnect and returns its public addresses. NOVA only stores
/// the addresses; signing stays in the user's wallet app.
class WalletConnectService {
  ReownAppKitModal? _modal;

  Future<({String? evm, String? sol, String? walletName})?> connect(BuildContext context) async {
    final modal = ReownAppKitModal(
      context: context,
      projectId: AppConfig.reownProjectId,
      metadata: const PairingMetadata(
        name: 'NOVA Finance',
        description: 'Your Money. Your Crypto. Your World.',
        url: AppConfig.appUrl,
        icons: ['https://thetechguydev.github.io/NovaApp/icons/Icon-192.png'],
        redirect: Redirect(native: 'novafinance://', universal: AppConfig.appUrl),
      ),
      disconnectOnDispose: false,
    );
    _modal = modal;
    await modal.init();

    final done = Completer<({String? evm, String? sol, String? walletName})?>();
    void onConnect(ModalConnect? e) {
      if (done.isCompleted) return;
      final s = modal.session;
      done.complete((
        evm: s?.getAddress('eip155'),
        sol: s?.getAddress('solana'),
        walletName: s?.peer?.metadata.name,
      ));
    }

    modal.onModalConnect.subscribe(onConnect);
    if (modal.isConnected) onConnect(null);
    if (!done.isCompleted) {
      await modal.openModalView();
      // Closing the sheet without connecting ends the attempt.
      if (!done.isCompleted && !modal.isConnected) {
        Future.delayed(const Duration(minutes: 2), () {
          if (!done.isCompleted) done.complete(null);
        });
      }
    }
    final result = await done.future;
    modal.onModalConnect.unsubscribe(onConnect);
    return result;
  }

  Future<void> disconnect() async {
    try {
      await _modal?.disconnect();
    } catch (_) {}
  }
}
