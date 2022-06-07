import QtQuick 2.0
import MuseScore 3.0
import QtQuick.Controls 1.1
import QtQuick.Controls.Styles 1.3
import QtQuick.Layouts 1.1

MuseScore {
    menuPath: "Plugins.Annotations"
    description: "Allows adding annotations/comments to a score"
    pluginType: "dock"
    version: "1.0"
    requiresScore: false

    property var activeScore: null; // Keep a reference to curScore to be able to detect switching scores
    property var commentablePositionSelected: false;
    property var selectedElement: null;

    onRun: {
        loadCurScoreData();
    }

    onScoreStateChanged : {
        //console.log("onScoreStateChanged", 
        //    "\tselectionChanged", state.selectionChanged,
        //    "\texcerptsChanged", state.excerptsChanged,
        //    "\tinstrumentsChanged", state.instrumentsChanged,
        //    "\n\tLayoutTicks", state.startLayoutTick, state.endLayoutTick,
        //    "\n\tundoRedo", state.undoRedo
        //);
        if (state.selectionChanged) {
            // First validate score changes
            if (!curScore.is(activeScore)) {
                loadCurScoreData();
            }

            // Now check selected element
            if (curScore) {
                if (   curScore.selection
                    && curScore.selection.elements
                    && (curScore.selection.elements.length === 1)
                ) {
                    selectedElement = curScore.selection.elements[0];
                    // Can we add a comment for this selection?
                    commentablePositionSelected = (selectedElement.type === Element.NOTE)
                                               || (selectedElement.type === Element.REST);
                    // Did we select a possible comment ?
                    if (selectedElement.type === Element.STAFF_TEXT) {
                        if (selectedElement.text == '…') {
                            //console.log('Candidate comment marker selected', selectedElement.parent.tick, selectedElement.track);
                            // Try to find a matching comment
                            for (var commentIdx = commentsModel.count; commentIdx-- > 0; ) {
                                var commentItem = commentsModel.get(commentIdx);
                                if (commentItem.staffTextRef && (commentItem.staffTextRef.is(selectedElement))) {
                                    //console.log("Found this comment", commentIdx);
                                    break;
                                }
                            }
                            if (commentIdx === -1) {
                                console.log("Matching comment not found");
                            }
                            commentsListView.currentIndex = commentIdx;
                        }
                        else { // Wrong text contents -> not a comment
                            commentsListView.currentIndex = -1;
                        }
                    }
                    else { // No STAFF_TEXT
                        commentsListView.currentIndex = -1;
                    }
                }
                else { // Did not select a single element
                    selectedElement = null;
                    commentablePositionSelected = false;
                    commentsListView.currentIndex = -1;
                }
            }
            else {
                // No more score selected, so most certainly no element in it either
                selectedElement = null;
                commentablePositionSelected = false;
                commentsModel.clear();
            }
        }
    } //onScoreStateChanged

    function loadCurScoreData() {
        //console.log("Changing active score to:", curScore.title, "("+curScore.scoreName+")");
        activeScore = curScore;

        selectedElement = null;
        commentablePositionSelected = false;
        commentsModel.clear();
        commentsListView.currentIndex = -1;

        var commentsToRestore = curScore.metaTag('Plugin-Annotations');
        commentsToRestore = JSON.parse((commentsToRestore == '') ? '[]' : commentsToRestore);
        console.log("Detected", commentsToRestore.length, "comments");

        // Attempt to link them to staff texts
        for (var commentIdx = 0; commentIdx < commentsToRestore.length; ++commentIdx) {
            //console.log("Restoring\n", commentsToRestore[commentIdx].comment,
            //            "\nfor Track", commentsToRestore[commentIdx].track, "and tick", commentsToRestore[commentIdx].tick);
            var cur = curScore.newCursor();
            cur.track = commentsToRestore[commentIdx].track;
            cur.rewindToTick(commentsToRestore[commentIdx].tick);
            var anns = cur.segment.annotations;
            var staffText = null;
            for (var ai = 0; ai < anns.length; ++ai) {
                if (   (anns[ai].type === Element.STAFF_TEXT)
                    && (anns[ai].text == '…')
                    && (anns[ai].track === commentsToRestore[commentIdx].track)
                ) {
                    // Found our reference
                    staffText = anns[ai];
                    break;
                }
            }

            // Register
            if (staffText !== null) {
                commentsModel.append({
                    comment: commentsToRestore[commentIdx].comment,
                    staffTextRef: staffText
                });
            }
        }
        console.log("Restored", commentsModel.count, "comments");
    }

    function commentsToJSON() {
        var commentsArray = [];
        for (var commentIdx = 0; commentIdx < commentsModel.count; ++commentIdx) {
            var existingComment = commentsModel.get(commentIdx);
            commentsArray.push({
                'comment': existingComment.comment,
                'track': existingComment.staffTextRef.track,
                'tick': existingComment.staffTextRef.parent.tick // Tick lives on the Segment, not the Element
            });
        }
        return JSON.stringify(commentsArray);
    }
    
    function closeAddCommentLayout() {
        addCommentLayout.visible = false; //.state = "hidden";
        commentsListView.focus = true;
    }

    ListModel {
        id: commentsModel
//        ListElement {
//            comment: "comment text"
//            staffTextRef: null | Element::STAFF_TEXT
//        }
    }

    Component {
        id: commentsViewDelegate
        Rectangle {
            property var iAmActive: ListView.isCurrentItem

            color: iAmActive ? "#ffffffff" : "#33000000"
            border.width: 1
            border.color: (staffTextRef != null) ? "#666" : "#f00"
            radius: 15

            width: parent.width
            height: cvdColumn.childrenRect.height

            MouseArea {
                anchors.fill: parent
                onClicked: commentsListView.currentIndex = index
            }

            ColumnLayout {
                id: cvdColumn
                spacing: 1
                width: parent.width

                Label {
                    Layout.fillWidth: true
                    padding: 10
                    text: comment
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: iAmActive ? 0x7FFFFFFF : 10
                }
                //Label {
                //    text: staffTextRef.toString()
                //}
            }
        }
    }

    anchors.fill: parent

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 5
        spacing: 5

        RowLayout {
            id: topButtons
            width: parent.width

            Button {
                enabled: commentablePositionSelected
                text: qsTranslate('Ms::ScoreView', 'Add')
                style: ButtonStyle {
                    background: Rectangle {
                        implicitWidth: 80
                        border.width: control.activeFocus ? 2 : 1
                        border.color: "#080"
                        radius: 6
                        gradient: Gradient {
                            GradientStop { position: 0 ; color: (control.enabled) ? (control.pressed ? "#0c6" : "#0a4") : "#686" }
                            GradientStop { position: 1 ; color: (control.enabled) ? (control.pressed ? "#0a4" : "#082") : "#686" }
                        }
                    }
                }
                onClicked: {
                    // Show an empty Add Form
                    newCommentTxt.text = '';
                    addCommentLayout.visible = true;//.state = "visible";
                }
            }

            Item { // Spacer
                Layout.fillWidth: true
            }

            Button {
                enabled: (commentsListView.currentItem)
                text: qsTranslate('Ms::MuseScore', 'Delete')
                style: ButtonStyle {
                    background: Rectangle {
                        implicitWidth: 80
                        border.width: control.activeFocus ? 2 : 1
                        border.color: "#800"
                        radius: 6
                        gradient: Gradient {
                            GradientStop { position: 0 ; color: (control.enabled) ? (control.pressed ? "#f66" : "#e44") : "#866" }
                            GradientStop { position: 1 ; color: (control.enabled) ? (control.pressed ? "#e44" : "#c22") : "#866" }
                        }
                    }
                }
                Layout.alignment: Qt.AlignRight

                onClicked: {
                    // Remove linked Staff Text
                    console.log("Remove selected Comment");
                    curScore.startCmd();
                    removeElement(commentsModel.get(commentsListView.currentIndex).staffTextRef);
                    curScore.endCmd();

                    // Remove comment
                    commentsModel.remove(commentsListView.currentIndex);
                    commentsListView.currentIndex = -1;

                    curScore.setMetaTag('Plugin-Annotations', commentsToJSON());
                    //console.log("Resulting commentsModel:", curScore.metaTag('Plugin-Annotations'));
                }
            }
        }

        ListView {
            id: commentsListView

            anchors.bottom: parent.bottom
            anchors.top: topButtons.bottom
            anchors.topMargin: 5
            anchors.left: parent.left
            anchors.right: parent.right
            Layout.fillHeight: true
            spacing: 5

            clip: true
            boundsBehavior: Flickable.StopAtBounds

            model: commentsModel
            delegate: commentsViewDelegate

            focus: true // Allow for up/down keyboard navigation
            onCurrentIndexChanged: {
                //console.log("New ListView index", currentIndex);
                if (currentIndex !== -1) {
                    if (!(   curScore.selection && curScore.selection.elements
                          && (curScore.selection.elements.length === 1)
                          && (curScore.selection.elements[0].is(commentsModel.get(currentIndex).staffTextRef))
                        )
                    ) {
                        ////////////////////////////////////////////////////////////////
                        // WARNING: If the corresponding Staff Text was deleted       //
                        //          we still have a stale (seemingly valid) reference //
                        //          but attempting to select it will CRASH MuseScore! //
                        ////////////////////////////////////////////////////////////////
                        if (commentsModel.get(currentIndex).staffTextRef) {
                            //console.log("Attempt to select", commentsModel.get(currentIndex).staffTextRef, "of currentItem", commentsModel.get(currentIndex));
                            /*var selectedResult = */curScore.selection.select(commentsModel.get(currentIndex).staffTextRef);
                            //console.log("Attempted to select staffTextRef", selectedResult);
                        }
                    }
                    //else {
                    //      console.log("Corresponding Staff Text already selected");
                    //}
                }
                // else { nothing selected }
            }
        }

        ColumnLayout {
            id: addCommentLayout
            anchors.fill: parent
            spacing: 5

            visible: false

            RowLayout {
                id: addCommentTopButtons
                width: parent.width

                Button {
                    enabled: (newCommentTxt.length > 0)
                    text: qsTranslate('Ms::ScoreView', 'Add')
                    style: ButtonStyle {
                        background: Rectangle {
                            implicitWidth: 80
                            border.width: control.activeFocus ? 2 : 1
                            border.color: "#080"
                            radius: 6
                            gradient: Gradient {
                                GradientStop { position: 0 ; color: (control.enabled) ? (control.pressed ? "#0c6" : "#0a4") : "#686" }
                                GradientStop { position: 1 ; color: (control.enabled) ? (control.pressed ? "#0a4" : "#082") : "#686" }
                            }
                        }
                    }
                    onClicked: {
                        // Insert Staff Text - find tick reference
                        var segment = selectedElement;
                        do {
                            segment = segment.parent;
                        } while (segment.type !== Element.SEGMENT);
                        // Insert Staff Text - go to it
                        var cursor = curScore.newCursor();
                        cursor.track = selectedElement.track;
                        cursor.rewindToTick(segment.tick);
                        // Insert Staff Text - create and style element
                        var staffText = newElement(Element.STAFF_TEXT);
                        staffText.text = '…';
                        staffText.fontStyle    = 1; // Bold
                        staffText.frameType    = 1; // Rectangle
                        staffText.frameWidth   = 0.15;
                        staffText.framePadding = 0.75;
                        staffText.frameRound   = 50;
                        staffText.frameFgColor = "#666666";
                        staffText.frameBgColor = "#80ffff7f";
                        // Insert Staff Text - add it
                        curScore.startCmd();
                        cursor.add(staffText);
                        curScore.endCmd();

                        var newComment = {
                            comment: newCommentTxt.text,
                            staffTextRef: staffText
                        };
                        // Find insertion point, scan by tick, then by track
                        var newIdx = 0;
                        while (newIdx < commentsModel.count) {
                            var compareTo = commentsModel.get(newIdx);
                            console.log("Comparing to", compareTo);
                            console.log("compareTo.comment", compareTo.comment);
                            console.log("compareTo.staffTextRef", compareTo.staffTextRef);
                            if (   (compareTo.staffTextRef.parent.tick > segment.tick)
                                || (   (compareTo.staffTextRef.parent.tick === segment.tick)
                                    && (compareTo.staffTextRef.track >= selectedElement.track)
                                )
                            ) {
                                break; // break while loop, insertion position found
                            }
                            else {
                                ++newIdx;
                            }
                        }
                        commentsModel.insert(newIdx, newComment);
                        commentsListView.currentIndex = newIdx;

                        curScore.setMetaTag('Plugin-Annotations', commentsToJSON());
                        //console.log("Resulting commentsModel:", curScore.metaTag('Plugin-Annotations'));

                        closeAddCommentLayout();
                    }
                }

                Item { // Spacer
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTranslate('Ms::MuseScore', 'Cancel')
                    style: ButtonStyle {
                        background: Rectangle {
                            implicitWidth: 80
                            border.width: control.activeFocus ? 2 : 1
                            border.color: "#888"
                            radius: 6
                            gradient: Gradient {
                                GradientStop { position: 0 ; color: control.pressed ? "#eee" : "#ddd" }
                                GradientStop { position: 1 ; color: control.pressed ? "#ddd" : "#ccc" }
                            }
                        }
                    }
                    Layout.alignment: Qt.AlignRight

                    onClicked: {
                        closeAddCommentLayout();
                    }
                }
            }

            Rectangle {
                color: "#fff"
                border.width: 3
                border.color: "#333"
                radius: 15

                anchors.top: addCommentTopButtons.bottom
                anchors.topMargin: 5
                anchors.left: parent.left
                anchors.right: parent.right
                height: 240

                MouseArea { // Added this to capture margin clicks and prevent them to propagate downwards
                    anchors.fill: parent
                    onClicked: newCommentTxt.focus = true
                }

                TextArea {
                    id: newCommentTxt
                    anchors.fill: parent
                    anchors.margins: 10

                    backgroundVisible: false
                    //textMargin: 10
                    focus: true
                    wrapMode: Text.Wrap
                }
            }
        } //addCommentLayout

    } //mainLayout

}
