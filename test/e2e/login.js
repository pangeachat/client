// Signing a participant in, WITHOUT pixel coordinates.
//
// The version this replaces clicked six fixed points -- (500,650) for "Login
// to my account", (500,592) for "Email", (500,487) for the username box, and
// so on. That is the exact failure the harness's own header condemns: after a
// layout change those clicks land on empty space, the run "succeeds" because
// nothing checks, and every scenario after it drives a page nobody is signed
// in to. Worse, it was a MACOS login: the field was cleared with Meta+A, which
// selects nothing on Linux.
//
// So this reads the screen instead. Flutter publishes a real accessibility
// tree once its hidden placeholder is clicked (see ui.js), which gives labels
// for the buttons and genuine <input> elements for the text fields. Each step
// finds its target or fails saying what WAS on screen, and the whole thing
// ends by proving the login form is gone rather than by sleeping and hoping.
const ui = require('./ui');
const cfg = require('./config');

const { wait } = ui;

// The entry control on the homeserver screen, and the submit button on the
// form, are both called some variant of "Login". They are told apart by
// state, not by wording: if a password field is on screen we are on the form.
const LOGIN_ENTRY = /(log ?in|sign ?in)/i;
const SUBMIT = /^\s*(log ?in|login|sign ?in)\s*$/i;
// The sign-in-method chooser. "Email" first because that is the one the app
// actually offers for these accounts -- its field takes a bare username too.
const METHOD = [/^\s*email\s*$/i, /^\s*username\s*$/i];
// Anchored, so "Forgot password?" is not mistaken for the field itself.
const PASSWORD_LABEL = /^\s*password\s*$/i;
const USERNAME_LABEL = /^\s*(username|user name|email|email address)\s*$/i;

async function shot(page, name) {
  const file = cfg.shot(`${name}.png`);
  await page.screenshot({ path: file }).catch(() => {});
  return file;
}

/// The first visible, labelled node matching a pattern, as a click point.
/// Prefers a real button, for the same reason ui.findRect does: an
/// IconButton's tooltip repeats its label and clicking the tooltip does
/// nothing at all.
async function findMatch(page, re, { anyNode = false } = {}) {
  return page.evaluate(
    (source, flags, anyNode) => {
      const pattern = new RegExp(source, flags);
      // A label reaches the tree two ways. Most controls carry `aria-label`;
      // some -- the onboarding buttons among them -- publish their text as
      // the node's own content instead, and reading only the attribute made
      // the whole welcome screen look like a single node called "Welcome
      // page" with no way past it. Only the node's OWN text counts, or a
      // parent group reads as every button inside it at once.
      const nodes = [...document.querySelectorAll('flt-semantics')];
      const nameOf = (e) => {
        const aria = e.getAttribute('aria-label');
        if (aria && aria.trim()) return aria.trim();
        const own = [...e.childNodes]
          .filter((n) => n.nodeType === Node.TEXT_NODE)
          .map((n) => n.textContent || '')
          .join('')
          .trim();
        return own;
      };
      const hits = nodes.filter((e) => {
        if (!pattern.test(nameOf(e))) return false;
        const r = e.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      // A real button, or nothing. The login page carries the heading "Login
      // to my account" ABOVE the three method buttons, and taking that as the
      // way forward clicked a piece of text once a second until the round
      // budget ran out.
      const hit = hits.find((e) => e.getAttribute('role') === 'button')
        || (anyNode ? hits[0] : null);
      if (!hit) return null;
      const r = hit.getBoundingClientRect();
      return {
        x: r.x + r.width / 2,
        y: r.y + r.height / 2,
        label: nameOf(hit),
      };
    },
    re.source,
    re.flags,
    anyNode,
  );
}

/// Every text box currently on screen, top to bottom.
///
/// With semantics on, Flutter backs each editable field with an <input>, so
/// these are real elements that can be clicked, cleared and typed into by
/// handle -- no coordinates, and no guess about which box is which: an
/// obscured field carries type="password".
async function textFields(page) {
  const handles = await page.$$('flt-semantics input, flt-semantics textarea');
  const fields = [];
  for (const handle of handles) {
    const box = await handle.boundingBox().catch(() => null);
    if (!box || box.width <= 0 || box.height <= 0) continue;
    const info = await handle
      .evaluate((el) => ({
        type: (el.getAttribute('type') || 'text').toLowerCase(),
        label: el.getAttribute('aria-label') || el.getAttribute('placeholder') || '',
      }))
      .catch(() => ({ type: 'text', label: '' }));
    fields.push({ handle, box, ...info });
  }
  fields.sort((a, b) => a.box.y - b.box.y);
  return fields;
}

const isPassword = (f) => f.type === 'password' || /password/i.test(f.label);

/// Clears a field and types into it.
///
/// Triple-click selects what is already there, which matters because these
/// profiles persist: a box can come back with the last run's value in it. The
/// keyboard fallback uses the platform's own select-all rather than Meta,
/// which is a macOS-only assumption that would have silently appended.
async function fill(page, field, value) {
  try {
    await field.handle.click({ clickCount: 3 });
  } catch (_) {
    await page.mouse.click(field.box.x + field.box.width / 2, field.box.y + field.box.height / 2);
    const selectAll = process.platform === 'darwin' ? 'Meta' : 'Control';
    await page.keyboard.down(selectAll);
    await page.keyboard.press('a');
    await page.keyboard.up(selectAll);
  }
  await wait(300);
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 25 });
}

/// The same thing for a build whose semantic text fields carry no <input>.
///
/// The label is still published, so the field can be found by name and only
/// its own rect clicked. That is a position again -- but a position derived
/// from the label THIS run, not one written down last year, and settle()
/// proves afterwards that the form actually went away.
async function fillByLabel(page, re, value) {
  const hit = await findMatch(page, re);
  if (!hit) return false;
  await page.mouse.click(hit.x, hit.y);
  await wait(400);
  const selectAll = process.platform === 'darwin' ? 'Meta' : 'Control';
  await page.keyboard.down(selectAll);
  await page.keyboard.press('a');
  await page.keyboard.up(selectAll);
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 25 });
  return true;
}

/// Waits for the Flutter app to have painted anything at all. A page still
/// booting answers every question with "not there", and a step that believes
/// it goes looking for a login form on a blank canvas.
async function waitForApp(page, { timeout = 40000 } = {}) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const up = await page
      .evaluate(() =>
        !!document.querySelector('flt-glass-pane, flt-semantics-placeholder')
        || (document.body.innerText || '').trim().length > 0)
      .catch(() => false);
    if (up) return true;
    await wait(1000);
  }
  return false;
}

/// Which account this profile is already signed in as, if it can be read.
///
/// Best effort: the client keeps its session in IndexedDB, and only some
/// builds mirror the user id into localStorage. A null here means "cannot
/// tell", never "not signed in" -- the route is what answers that.
async function signedInAs(page) {
  return page
      .evaluate(() => {
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i) || '';
          if (!/user_?id/i.test(key)) continue;
          const value = localStorage.getItem(key) || '';
          const at = value.match(/@[^"\s,}]+:[^"\s,}]+/);
          if (at) return at[0];
        }
        return null;
      })
      .catch(() => null);
}

/// Signs `user` in, and PROVES the form went away.
///
/// Returns the URL it ended on, as the old one did. Idempotent on a persisted
/// profile: if the app comes up already signed in there is nothing to do, and
/// the old harness's habit of clicking through a login screen that was not
/// there is how a run ended up somewhere nobody meant it to be.
async function login(page, user, pass, tag = 'login') {
  await page.goto(cfg.appUrl, { waitUntil: 'domcontentloaded' });
  if (!(await waitForApp(page))) {
    const file = await shot(page, `${tag}-never-painted`);
    throw new Error(
      `the app never painted at ${cfg.appUrl} -- is the web build being `
      + `served? Screenshot: ${file}`,
    );
  }

  // Rounds rather than a fixed script: the app shows the homeserver screen,
  // then the method chooser, then the form, and a persisted profile can start
  // at any of them (or past all of them).
  for (let round = 1; round <= 12; round++) {
    await ui.enableSemantics(page);
    await wait(1200);

    const fields = await textFields(page);
    const password = fields.find(isPassword);
    if (password) {
      const username = fields.find((f) => f !== password && !isPassword(f));
      if (!username) {
        const file = await shot(page, `${tag}-no-username-box`);
        throw new Error(
          'found a password box but no username box. On screen: '
          + `${JSON.stringify(await ui.labels(page))}. Screenshot: ${file}`,
        );
      }
      await fill(page, username, user);
      await fill(page, password, pass);
      return submitAndSettle(page, tag);
    }

    // No <input> behind the fields, but the form is plainly on screen.
    if (await findMatch(page, PASSWORD_LABEL)) {
      const filled = (await fillByLabel(page, USERNAME_LABEL, user))
        && (await fillByLabel(page, PASSWORD_LABEL, pass));
      if (filled) return submitAndSettle(page, tag);
    }

    // The chooser first: on the login page BOTH match, and only one of them
    // leads anywhere.
    const next = (await firstOf(page, METHOD))
      || (await findMatch(page, LOGIN_ENTRY));
    if (next) {
      await page.mouse.click(next.x, next.y);
      await wait(2500);
      continue;
    }

    // No form, no way into one. Either the profile is already signed in --
    // which is the common case, these profiles persist -- or the app is
    // somewhere unexpected.
    //
    // "Signed in" is not "the page has words on it": a profile left behind by
    // an earlier run can hold the OTHER account, and accepting it here sends
    // the whole scenario off as the wrong person, failing later in a way that
    // reads like a product bug. The client keeps its session in localStorage,
    // so the account is knowable without touching the UI.
    // The app routes by path and lands a signed-in account on "/", which is
    // also where the welcome carousel lives -- so the URL cannot answer this
    // and the screen has to. Both entry screens name themselves in the
    // semantics tree; anything else, with content on it, is the app proper.
    const onEntry = await findMatch(page, /^(welcome page|login page)$/i, {
      anyNode: true,
    });
    const text = await page
        .evaluate(() => (document.body.innerText || '').trim())
        .catch(() => '');
    if (!onEntry && text.length > 0 && round >= 2) {
      const who = await signedInAs(page);
      if (who && !who.toLowerCase().startsWith(`@${user.toLowerCase()}:`)) {
        const file = await shot(page, `${tag}-wrong-account`);
        throw new Error(
          `this profile is signed in as ${who}, not ${user}. Delete the `
          + `profile directory and run again. Screenshot: ${file}`,
        );
      }
      return page.evaluate(() => location.href);
    }
    await wait(2000);
  }

  const file = await shot(page, `${tag}-login-stuck`);
  throw new Error(
    `could not sign ${user} in: no password box and no way to reach one. `
    + `On screen: ${JSON.stringify(await ui.labels(page))}. Screenshot: ${file}`,
  );
}

/// Submits, and waits for the form to be gone rather than for a clock.
async function submitAndSettle(page, tag) {
  await shot(page, `${tag}-filled`);
  const submit = await findMatch(page, SUBMIT);
  if (submit) {
    await page.mouse.click(submit.x, submit.y);
  } else {
    // Enter submits the form the same way the button does. Safe to fall back
    // to blindly, because settle() proves the form is gone: a press that did
    // nothing fails here rather than three scenarios later.
    await page.keyboard.press('Enter');
  }
  await settle(page, tag);
  return page.evaluate(() => location.href);
}

async function firstOf(page, patterns) {
  for (const re of patterns) {
    const hit = await findMatch(page, re);
    if (hit) return hit;
  }
  return null;
}

/// The login is not done when the button is clicked; it is done when the form
/// is gone. Sleeping seven seconds and moving on is what let a failed login
/// look like a slow one.
async function settle(page, tag, { timeout = 60000 } = {}) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    await wait(2000);
    const fields = await textFields(page).catch(() => []);
    const stillThere = fields.some(isPassword) || (await findMatch(page, PASSWORD_LABEL));
    if (!stillThere) {
      await shot(page, `${tag}-after`);
      return true;
    }
    await ui.enableSemantics(page).catch(() => {});
  }
  const file = await shot(page, `${tag}-login-failed`);
  throw new Error(
    `the login form is still on screen after ${timeout / 1000}s -- wrong password, or the `
    + `homeserver is not answering. On screen: ${JSON.stringify(await ui.labels(page))}. `
    + `Screenshot: ${file}`,
  );
}

module.exports = { login, wait, shot };
