document.addEventListener('DOMContentLoaded', function() {
  var dropzone = document.getElementById('dropzone');
  var fileInput = document.getElementById('statementFile');
  var browseBtn = document.getElementById('browseBtn');
  var fileName = document.getElementById('fileName');
  var fileSize = document.getElementById('fileSize');
  var fileChip = document.getElementById('fileChip');
  var uploadBtn = document.getElementById('uploadBtn');
  var form = document.getElementById('statementForm');
  var progressBar = document.getElementById('uploadProgressBar');
  var uploadProgress = document.getElementById('uploadProgress');
  var uploadSteps = document.getElementById('uploadSteps');
  var errorBox = document.getElementById('uploadError');
  var removeFileBtn = document.getElementById('removeFileBtn');

  if (!form) return;

  var uploadFailed = form.dataset.uploadFailed || '';
  var submitting = false;

  function clearFile() {
    fileInput.value = '';
    fileChip.classList.add('d-none');
    uploadBtn.disabled = true;
  }

  if (browseBtn) browseBtn.addEventListener('click', function() { fileInput.click(); });
  if (dropzone) dropzone.addEventListener('click', function(e) {
    if (e.target && e.target.id === 'browseBtn') return;
    fileInput.click();
  });

  if (removeFileBtn) removeFileBtn.addEventListener('click', clearFile);

  var unlockBtn = document.getElementById('unlockBtn');
  if (unlockBtn) {
    unlockBtn.addEventListener('click', function() { form.requestSubmit(uploadBtn); });
  }

  ['dragover', 'dragenter'].forEach(function(ev) {
    dropzone.addEventListener(ev, function(e) { e.preventDefault(); dropzone.classList.add('bg-primary-subtle'); });
  });
  ['dragleave', 'drop'].forEach(function(ev) {
    dropzone.addEventListener(ev, function(e) { e.preventDefault(); dropzone.classList.remove('bg-primary-subtle'); });
  });
  dropzone.addEventListener('drop', function(e) {
    if (e.dataTransfer.files.length) fileInput.files = e.dataTransfer.files;
    handleFile();
  });
  fileInput.addEventListener('change', handleFile);

  function handleFile() {
    var file = fileInput.files[0];
    if (!file) return;
    fileName.textContent = file.name;
    fileSize.textContent = file.size ? '(' + formatSize(file.size) + ')' : '';
    fileChip.classList.remove('d-none');
    uploadBtn.disabled = false;

    var isPdf = file.name.toLowerCase().endsWith('.pdf');
    var passwordCard = document.querySelector('.password-card');
    if (isPdf) {
      passwordCard.classList.remove('d-none');
    } else {
      passwordCard.classList.add('d-none');
      document.getElementById('statementPassword').value = '';
    }
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
  }

  function setStep(step, state, percent) {
    var item = uploadSteps && uploadSteps.querySelector('[data-upload-step="' + step + '"]');
    if (!item) return;
    var spinner = item.querySelector('[data-step-spinner]');
    var done = item.querySelector('[data-step-done]');
    var idle = item.querySelector('[data-step-idle]');
    if (spinner) spinner.classList.toggle('d-none', state !== 'active');
    if (done) done.classList.toggle('d-none', state !== 'done');
    if (idle) idle.classList.toggle('d-none', state !== 'idle');
    var readout = item.querySelector('[data-step-percent]');
    if (readout) readout.textContent = percent == null ? '' : Math.round(percent) + '%';
  }

  function showError(message) {
    if (!errorBox) return;
    errorBox.textContent = message || uploadFailed;
    errorBox.classList.remove('d-none');
    errorBox.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  form.addEventListener('submit', function(e) {
    if (submitting) { e.preventDefault(); return; }
    if (!window.XMLHttpRequest || !fileInput.files.length) return; // fall back to native submit

    e.preventDefault();
    submitting = true;
    document.getElementById('statementPasswordHidden').value = document.getElementById('statementPassword').value;
    if (errorBox) errorBox.classList.add('d-none');
    uploadSteps.classList.remove('d-none');
    uploadProgress.classList.remove('d-none');
    progressBar.style.width = '0%';
    setStep('upload', 'active', 0);
    setStep('analyze', 'idle');
    uploadBtn.disabled = true;

    var xhr = new XMLHttpRequest();
    xhr.open('POST', form.action, true);
    xhr.setRequestHeader('Accept', 'application/json');
    var token = document.querySelector("meta[name='csrf-token']");
    if (token) xhr.setRequestHeader('X-CSRF-Token', token.getAttribute('content'));

    xhr.upload.addEventListener('progress', function(ev) {
      if (!ev.lengthComputable) return;
      var pct = (ev.loaded / ev.total) * 100;
      progressBar.style.width = pct + '%';
      setStep('upload', 'active', pct);
    });
    xhr.upload.addEventListener('load', function() {
      progressBar.style.width = '100%';
      setStep('upload', 'done', 100);
      setStep('analyze', 'active');
    });

    xhr.addEventListener('load', function() {
      submitting = false;
      var data = {};
      try { data = JSON.parse(xhr.responseText); } catch (err) { /* keep {} */ }

      if (xhr.status >= 200 && xhr.status < 300 && data.ok && data.redirect_url) {
        setStep('analyze', 'done');
        window.location.assign(data.redirect_url);
        return;
      }

      setStep('analyze', 'idle');
      progressBar.style.width = '0%';
      uploadBtn.disabled = false;
      showError((data.errors || []).join(' '));
    });

    xhr.addEventListener('error', function() {
      submitting = false;
      setStep('analyze', 'idle');
      progressBar.style.width = '0%';
      uploadBtn.disabled = false;
      showError('');
    });

    xhr.send(new FormData(form));
  });
});
