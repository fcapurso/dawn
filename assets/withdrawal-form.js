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
    var emailInput = form.querySelector('input[name="contact[email]"]');
    openModal(
      orderInput && orderInput.value ? orderInput.value : '',
      emailInput && emailInput.value ? emailInput.value : ''
    );
  }

  // Primary path: the (type="button") button just opens the modal.
  btn.addEventListener('click', tryOpen);

  // Safety net: gate any native submit (e.g. Enter) behind the modal.
  form.addEventListener('submit', function (e) {
    if (confirmed) return; // confirmed path: allow native submit
    e.preventDefault();
    tryOpen();
  });

  function openModal(order, email) {
    var bodyTpl = btn.getAttribute('data-confirm-body') || '';
    var orderText = order ? '#' + order.replace(/^#/, '') : '';
    // Escape the template and each dynamic value separately, then join with
    // trusted (hardcoded, attribute-free) markup, so a malicious order number
    // or email can never inject real tags: only its own escaped text ends up
    // inside <strong>.
    // Function replacers, not replacement strings: a string replacement would
    // let an order/email value containing "$&", "$$", "$`" or "$'" splice in
    // extra template text via String.replace's special pattern syntax.
    // Dawn only loads two body-font weight files (regular + its resolved
    // "bold"), so intermediate font-weight values just snap to one of those
    // two extremes rather than rendering a true medium weight - bold reads as
    // too heavy for this font. Highlight with color instead of weight: keep
    // <strong> for semantics, override its default bold via CSS (see
    // .withdrawal-modal__highlight in withdrawal-form.liquid).
    var body = esc(bodyTpl)
      .replace('[order]', function () { return '<strong class="withdrawal-modal__highlight">' + esc(orderText) + '</strong>'; })
      .replace('[email]', function () { return '<strong class="withdrawal-modal__highlight">' + esc(email || '') + '</strong>'; })
      .replace(/\n/g, '<br>');

    var overlay = document.createElement('div');
    overlay.className = 'withdrawal-modal';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML =
      '<div class="withdrawal-modal__box" tabindex="-1">' +
      '<h2>' + esc(btn.getAttribute('data-confirm-title')) + '</h2>' +
      '<p>' + body + '</p>' +
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
