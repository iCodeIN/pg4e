<?php
require_once "../config.php";
require_once "sql_util.php";

use \Tsugi\Util\U;
use \Tsugi\Core\Settings;
use \Tsugi\Core\LTIX;
use \Tsugi\UI\SettingsForm;
use \Tsugi\UI\Lessons;

$LAUNCH = LTIX::requireData();
$p = $CFG->dbprefix;
$unique = getUnique($LAUNCH);

if ( ! $USER->instructor ) die("Must be instructor");

$redirect = false;
$postkeys = array('db_source', 'umsi_url', 'umsi_password', 'umsi_key', 'tunnel');
if ( U::get($_POST, 'update') ) {
    foreach($postkeys as $key) {
        $LAUNCH->context->settingsSet($key, U::get($_POST, $key));
        $redirect = true;
    }
}

if ( $redirect ) {
    // die();
    $_SESSION['success'] = 'Settings updated.';
    header("Location: ".addSession('index.php'));
    return;
}

$settings = $LAUNCH->context->settingsGetAll();

$umsi_password = U::get($settings, 'umsi_password');

// View
$OUTPUT->header();
$OUTPUT->bodyStart();
$OUTPUT->topNav();

// Settings button and dialog

echo('<div style="float: right;">');
echo('<a href="index.php"><button class="btn btn-info">Back</button></a> '."\n");
echo('</div>');

$OUTPUT->flashMessages();

$OUTPUT->welcomeUserCourse();

// echo("<pre>\n");var_dump($set);echo("</pre>\n");

?>
<p><b>Note:</b> This is a per-course configuration, not a per-link
configuration so <b>changing this configuration</b>
affects all of the links in a course.  So be careful.
</p>
<p>If you are using ElephantSQL or some other externally provisioned PostgreSQL
server, leave the UMSI provisioning values blank.
If this course using UMSI provisioning, please configure the API for this <b>course</b>.   
<form method="post">
<p>
<select name="db_source">
<option value="none">-- Please select the type of database server --</option>
<option value="umsi"
<?php if ( U::get($settings, "db_source") == 'umsi' ) echo('selected'); ?>
>UMSI</option>
<option value="elephant"
<?php if ( U::get($settings, "db_source") == 'elephant' ) echo('selected'); ?>
>ElephantSQL</option>
</select>
</p>
<p>UMSI_URL <input type="text" name="umsi_url" value="<?= htmlentities(U::get($settings, 'umsi_url')) ?>"></p>
<p>UMSI_KEY <input type="text" name="umsi_key" value="<?= htmlentities(U::get($settings, 'umsi_key')) ?>"></p>
<p>UMSI_PASSWORD 
<span id="pass" style="display:none"><input type="text" name="umsi_password" id="umsi_password" value="<?= htmlentities($umsi_password) ?>"/></span> (<a href="#" onclick="$('#pass').toggle();return false;">hide/show</a> <a href="#" onclick="copyToClipboard(this, '<?= htmlentities($umsi_password) ?>');return false;">copy</a>)</p>
<p>
Is there an ssh tunnel required?
<select name="tunnel">
<option value="no">No Tunnel<option>
<option value="yes"
<?php if ( U::get($settings, "tunnel") == 'yes' ) echo('selected'); ?>
>SSH Tunnel</option>
</select>
</p>
<input type="submit" name="update">
</form>

<?php
$OUTPUT->footer();

