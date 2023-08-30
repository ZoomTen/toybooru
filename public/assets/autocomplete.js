let autoComplete = document.createElement("ul");
autoComplete.id = "autocomplete";
document.body.appendChild(autoComplete);

function updateAutocomplete(word, attachedElement) {
  if (!autoComplete)
    return;
  word = word.trim();
  if (word.charAt(0) == "-")
    word = word.substring(1);
  if (word === "")
    return hideAutocomplete();
  let acr = new XMLHttpRequest();
  acr.addEventListener("load", (e) => {
    let content = JSON.parse(acr.responseText);
    if (content) {
      autoComplete.style.display = "block";
      autoComplete.style.left = `${attachedElement.offsetLeft}px`;
      autoComplete.style.top = `${attachedElement.offsetTop + attachedElement.offsetHeight - window.scrollY}px`;
      autoComplete.style.width = `${attachedElement.offsetWidth}px`;
      autoComplete.innerHTML = "";
      for (let entry in content) {
        let container = document.createElement("li");
        let link = document.createElement("a");
        link.href = "#";
        link.appendChild(document.createTextNode(entry));
        container.appendChild(link);
        autoComplete?.appendChild(container);
      }
    }
  });
  acr.open("get", "/autocomplete/" + word);
  acr.send();
}

function hideAutocomplete() {
  if (!autoComplete)
    return;
  autoComplete.style.display = "none";
}

function commonAutocompleteKeyup(el) {
  if (el.selectionStart !== el.value.length)
    return;
  let splitStuff = el.value.split(" ");
  updateAutocomplete(
    splitStuff[splitStuff.length - 1],
    // get last word
    el
  );
}

function commonAutocompleteBlur(e) {
  let target = e.target;
  let lostFocusTo = e.relatedTarget;
  if (lostFocusTo) {
    if (lostFocusTo.parentElement.parentElement.id != "autocomplete") {
      return;
    }
    if (lostFocusTo.tagName.toLowerCase() === "a") {
      let splitStuff = target.value.split(" ");
      let lastWord = splitStuff[splitStuff.length - 1];
      if (lastWord.charAt(0) == "-") {
        splitStuff[splitStuff.length - 1] = `-${lostFocusTo.innerText}`;
      } else {
        splitStuff[splitStuff.length - 1] = lostFocusTo.innerText;
      }
      target.value = splitStuff.join(" ");
      target.focus();
      target.selectionStart = target.value.length;
      hideAutocomplete();
    }
  } else {
    target.focus();
    target.selectionStart = target.value.length;
    hideAutocomplete();
  }
}

for (let hookedElement of [
  document.getElementById("searchInput"),
  document.getElementById("editTagBox"),
  document.getElementById("submitTagBox")
]) {
  if (hookedElement) {
    hookedElement.addEventListener(
      "keyup",
      (e) => {
        commonAutocompleteKeyup(e.target);
      }
    );
    hookedElement.addEventListener(
      "focusout",
      (e) => {
        commonAutocompleteBlur(e);
      }
    );
  }
}
