// Two-step confirmation for the withdrawal form.
// The visible button is type="button" so it can never natively submit;
// only the modal's Confirm submits via requestSubmit(). A submit listener
// is a safety net for stray native submits (e.g. Enter key).
(function () {
  var btn = document.querySelector('[data-withdrawal-submit]');
  if (!btn) return;
  var form = btn.closest('form');
  if (!form) return;
  var confirmed = false;

  function honeypotFilled() {
    var hp = form.querySelector('input[name="contact[Website]"]');
    return !!(hp && hp.value);
  }

  function tryOpen() {
    if (honeypotFilled()) return;
    if (document.querySelector('.withdrawal-modal')) return; // already open
    if (form.reportValidity && !form.reportValidity()) return; // native required-field check
    var orderInput = form.querySelector('input[name="contact[Order number]"]');
    openModal(orderInput && orderInput.value ? orderInput.value : '');
  }

  // Primary path: the (type="button") button just opens the modal.
  btn.addEventListener('click', tryOpen);

  // Safety net: gate any native submit (e.g. Enter) behind the modal.
  form.addEventListener('submit', function (e) {
    if (confirmed) return; // confirmed path: allow native submit
    e.preventDefault();
    tryOpen();
  });

  function openModal(order) {
    var bodyTpl = btn.getAttribute('data-confirm-body') || '';
    var orderText = order ? '#' + order.replace(/^#/, '') : '';
    var body = bodyTpl.replace('[order]', orderText);

    var overlay = document.createElement('div');
    overlay.className = 'withdrawal-modal';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML =
      '<div class="withdrawal-modal__box" tabindex="-1">' +
      '<h2>' + esc(btn.getAttribute('data-confirm-title')) + '</h2>' +
      '<p>' + esc(body) + '</p>' +
      '<div class="withdrawal-modal__actions">' +
      '<button type="button" class="button" data-ok>' + esc(btn.getAttribute('data-confirm-ok')) + '</button>' +
      '<button type="button" class="button button--secondary" data-cancel>' + esc(btn.getAttribute('data-confirm-cancel')) + '</button>' +
      '</div></div>';
    document.body.appendChild(overlay);

    // Focus the dialog box (NOT the Confirm button) so no keystroke can auto-confirm.
    overlay.querySelector('.withdrawal-modal__box').focus();

    overlay.querySelector('[data-ok]').addEventListener('click', function () {
      confirmed = true;
      close(overlay);
      if (form.requestSubmit) {
        form.requestSubmit();
      } else {
        form.submit();
      }
    });
    overlay.querySelector('[data-cancel]').addEventListener('click', function () { close(overlay); });
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(overlay); });
    document.addEventListener('keydown', function escClose(e) {
      if (e.key === 'Escape') {
        close(overlay);
        document.removeEventListener('keydown', escClose);
      }
    });
  }

  function close(el) {
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  function esc(s) {
    var d = document.createElement('div');
    d.textContent = s || '';
    return d.innerHTML;
  }
})();
