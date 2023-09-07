type Inputable = HTMLInputElement | HTMLTextAreaElement;
interface TagDef {
    t: string, // tag name
    c: number // tag counts
};

function isTagDef(a: any): a is TagDef {
    return "t" in a && "c" in a;
}

(function(d: Document, w: Window){
    // create autocomplete element here as it's a scripting-only thing
    let autoComplete = d.createElement("ul");
    autoComplete.id = "autocomplete";
    d.body.appendChild(autoComplete);

    function updateAutocomplete(word: string, attachedElement: Inputable) {
        if (!autoComplete) return;

        word = word.trim();
        if (word.charAt(0) == "-") word = word.substring(1);

        if (word == "") return hideAutocomplete();

        let acr = new XMLHttpRequest();
        acr.addEventListener("load", () => {
            let content = JSON.parse(acr.responseText);
            if (!(typeof content == "object" && content[0] != undefined)) return;

            // show autoComplete
            autoComplete.style.display = "block";
            autoComplete.style.left = `${attachedElement.offsetLeft}px`;
            autoComplete.style.top = `${attachedElement.offsetTop + attachedElement.offsetHeight - w.scrollY}px`;
            autoComplete.style.width = `${attachedElement.offsetWidth}px`;

            autoComplete.innerHTML = ""; // clear all in element
            // I could've just walked the DOM but that doesn't seem to work?

            for (let entry of content) {
                if (isTagDef(entry)) {
                    let container = d.createElement("li");
                    let link = d.createElement("a");
                    link.href = "#";
                    link.appendChild(d.createTextNode(entry.t));
                    container.appendChild(link);
                    autoComplete.appendChild(container);
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

    function commonAutocompleteKeyup(el: Inputable) {
        if (el.selectionStart !== el.value.length)
            return;
        let splitStuff = el.value.split(" ");
        updateAutocomplete(
            splitStuff[splitStuff.length - 1] || "", // get last word
            el
        );
    }

    function commonAutocompleteBlur(e: FocusEvent) {
        let target = e.target as Inputable;
        let lostFocusTo = e.relatedTarget as HTMLAnchorElement;
        if (lostFocusTo) {
            if (lostFocusTo.parentElement!.parentElement!.id != "autocomplete") {
                return;
            }
            if (lostFocusTo.tagName.toLowerCase() === "a") {
                let splitStuff = target.value.split(" ");
                let lastWord = splitStuff[splitStuff.length - 1];
                if (lastWord == undefined) return;
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
        d.getElementById("searchInput"),
        d.getElementById("editTagBox"),
        d.getElementById("submitTagBox")
    ]) {
        if (hookedElement) {
            hookedElement.addEventListener(
                "keyup",
                (e) => {
                    commonAutocompleteKeyup(e.target as Inputable);
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
})(document, window);
