namespace SRTTestbed
{
    partial class Form1
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.pictureBox1 = new System.Windows.Forms.PictureBox();
            this.splitContainer1 = new System.Windows.Forms.SplitContainer();
            this.pictureBox2 = new System.Windows.Forms.PictureBox();
            this.timer1 = new System.Windows.Forms.Timer(this.components);
            this.splitContainer2 = new System.Windows.Forms.SplitContainer();
            this.pixelTraceBox = new System.Windows.Forms.RichTextBox();
            this.panel1 = new System.Windows.Forms.Panel();
            this.animateCheckBox = new System.Windows.Forms.CheckBox();
            this.writeData = new System.Windows.Forms.Button();
            this.showBranchPredictionHitRateCheckbox = new System.Windows.Forms.CheckBox();
            this.ditherCheckbox = new System.Windows.Forms.CheckBox();
            this.rgb555DisplayCheckBox = new System.Windows.Forms.CheckBox();
            this.palettizedDisplayCheckbox = new System.Windows.Forms.CheckBox();
            this.regeneratePaletteButton = new System.Windows.Forms.Button();
            this.timer2 = new System.Windows.Forms.Timer(this.components);
            this.visualiseCullingCheckBox = new System.Windows.Forms.CheckBox();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainer1)).BeginInit();
            this.splitContainer1.Panel1.SuspendLayout();
            this.splitContainer1.Panel2.SuspendLayout();
            this.splitContainer1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.splitContainer2)).BeginInit();
            this.splitContainer2.Panel1.SuspendLayout();
            this.splitContainer2.Panel2.SuspendLayout();
            this.splitContainer2.SuspendLayout();
            this.panel1.SuspendLayout();
            this.SuspendLayout();
            // 
            // pictureBox1
            // 
            this.pictureBox1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pictureBox1.Location = new System.Drawing.Point(0, 0);
            this.pictureBox1.Name = "pictureBox1";
            this.pictureBox1.Size = new System.Drawing.Size(528, 437);
            this.pictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox1.TabIndex = 0;
            this.pictureBox1.TabStop = false;
            this.pictureBox1.MouseClick += new System.Windows.Forms.MouseEventHandler(this.pictureBox1_MouseClick);
            // 
            // splitContainer1
            // 
            this.splitContainer1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.splitContainer1.Location = new System.Drawing.Point(0, 0);
            this.splitContainer1.Name = "splitContainer1";
            // 
            // splitContainer1.Panel1
            // 
            this.splitContainer1.Panel1.Controls.Add(this.pictureBox1);
            // 
            // splitContainer1.Panel2
            // 
            this.splitContainer1.Panel2.Controls.Add(this.pictureBox2);
            this.splitContainer1.Size = new System.Drawing.Size(1042, 437);
            this.splitContainer1.SplitterDistance = 528;
            this.splitContainer1.TabIndex = 1;
            // 
            // pictureBox2
            // 
            this.pictureBox2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pictureBox2.Location = new System.Drawing.Point(0, 0);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(510, 437);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 1;
            this.pictureBox2.TabStop = false;
            // 
            // timer1
            // 
            this.timer1.Enabled = true;
            this.timer1.Interval = 16;
            this.timer1.Tick += new System.EventHandler(this.timer1_Tick);
            // 
            // splitContainer2
            // 
            this.splitContainer2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.splitContainer2.Location = new System.Drawing.Point(0, 0);
            this.splitContainer2.Name = "splitContainer2";
            this.splitContainer2.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // splitContainer2.Panel1
            // 
            this.splitContainer2.Panel1.Controls.Add(this.splitContainer1);
            // 
            // splitContainer2.Panel2
            // 
            this.splitContainer2.Panel2.Controls.Add(this.pixelTraceBox);
            this.splitContainer2.Panel2.Controls.Add(this.panel1);
            this.splitContainer2.Size = new System.Drawing.Size(1042, 669);
            this.splitContainer2.SplitterDistance = 437;
            this.splitContainer2.TabIndex = 2;
            // 
            // pixelTraceBox
            // 
            this.pixelTraceBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pixelTraceBox.Font = new System.Drawing.Font("Consolas", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.pixelTraceBox.Location = new System.Drawing.Point(0, 0);
            this.pixelTraceBox.Name = "pixelTraceBox";
            this.pixelTraceBox.Size = new System.Drawing.Size(1042, 192);
            this.pixelTraceBox.TabIndex = 0;
            this.pixelTraceBox.Text = "";
            // 
            // panel1
            // 
            this.panel1.Controls.Add(this.visualiseCullingCheckBox);
            this.panel1.Controls.Add(this.animateCheckBox);
            this.panel1.Controls.Add(this.writeData);
            this.panel1.Controls.Add(this.showBranchPredictionHitRateCheckbox);
            this.panel1.Controls.Add(this.ditherCheckbox);
            this.panel1.Controls.Add(this.rgb555DisplayCheckBox);
            this.panel1.Controls.Add(this.palettizedDisplayCheckbox);
            this.panel1.Controls.Add(this.regeneratePaletteButton);
            this.panel1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panel1.Location = new System.Drawing.Point(0, 192);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(1042, 36);
            this.panel1.TabIndex = 1;
            // 
            // animateCheckBox
            // 
            this.animateCheckBox.AutoSize = true;
            this.animateCheckBox.Location = new System.Drawing.Point(467, 9);
            this.animateCheckBox.Name = "animateCheckBox";
            this.animateCheckBox.Size = new System.Drawing.Size(64, 17);
            this.animateCheckBox.TabIndex = 6;
            this.animateCheckBox.Text = "Animate";
            this.animateCheckBox.UseVisualStyleBackColor = true;
            this.animateCheckBox.CheckedChanged += new System.EventHandler(this.animateCheckBox_CheckedChanged);
            // 
            // writeData
            // 
            this.writeData.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.writeData.Location = new System.Drawing.Point(955, 6);
            this.writeData.Name = "writeData";
            this.writeData.Size = new System.Drawing.Size(75, 23);
            this.writeData.TabIndex = 5;
            this.writeData.Text = "Write data";
            this.writeData.UseVisualStyleBackColor = true;
            this.writeData.Click += new System.EventHandler(this.writeData_Click);
            // 
            // showBranchPredictionHitRateCheckbox
            // 
            this.showBranchPredictionHitRateCheckbox.AutoSize = true;
            this.showBranchPredictionHitRateCheckbox.Location = new System.Drawing.Point(288, 9);
            this.showBranchPredictionHitRateCheckbox.Name = "showBranchPredictionHitRateCheckbox";
            this.showBranchPredictionHitRateCheckbox.Size = new System.Drawing.Size(173, 17);
            this.showBranchPredictionHitRateCheckbox.TabIndex = 4;
            this.showBranchPredictionHitRateCheckbox.Text = "Show branch prediction hit rate";
            this.showBranchPredictionHitRateCheckbox.UseVisualStyleBackColor = true;
            this.showBranchPredictionHitRateCheckbox.CheckedChanged += new System.EventHandler(this.showBranchPredictionHitRateCheckbox_CheckedChanged);
            // 
            // ditherCheckbox
            // 
            this.ditherCheckbox.AutoSize = true;
            this.ditherCheckbox.Location = new System.Drawing.Point(228, 9);
            this.ditherCheckbox.Name = "ditherCheckbox";
            this.ditherCheckbox.Size = new System.Drawing.Size(54, 17);
            this.ditherCheckbox.TabIndex = 3;
            this.ditherCheckbox.Text = "Dither";
            this.ditherCheckbox.UseVisualStyleBackColor = true;
            this.ditherCheckbox.CheckedChanged += new System.EventHandler(this.ditherCheckbox_CheckedChanged);
            // 
            // rgb555DisplayCheckBox
            // 
            this.rgb555DisplayCheckBox.AutoSize = true;
            this.rgb555DisplayCheckBox.Location = new System.Drawing.Point(120, 9);
            this.rgb555DisplayCheckBox.Name = "rgb555DisplayCheckBox";
            this.rgb555DisplayCheckBox.Size = new System.Drawing.Size(102, 17);
            this.rgb555DisplayCheckBox.TabIndex = 2;
            this.rgb555DisplayCheckBox.Text = "RGB555 display";
            this.rgb555DisplayCheckBox.UseVisualStyleBackColor = true;
            this.rgb555DisplayCheckBox.CheckedChanged += new System.EventHandler(this.rgb555DisplayCheckBox_CheckedChanged);
            // 
            // palettizedDisplayCheckbox
            // 
            this.palettizedDisplayCheckbox.AutoSize = true;
            this.palettizedDisplayCheckbox.Location = new System.Drawing.Point(3, 10);
            this.palettizedDisplayCheckbox.Name = "palettizedDisplayCheckbox";
            this.palettizedDisplayCheckbox.Size = new System.Drawing.Size(111, 17);
            this.palettizedDisplayCheckbox.TabIndex = 1;
            this.palettizedDisplayCheckbox.Text = "256 colour display";
            this.palettizedDisplayCheckbox.UseVisualStyleBackColor = true;
            this.palettizedDisplayCheckbox.CheckedChanged += new System.EventHandler(this.palettizedDisplayCheckbox_CheckedChanged);
            // 
            // regeneratePaletteButton
            // 
            this.regeneratePaletteButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.regeneratePaletteButton.Location = new System.Drawing.Point(874, 7);
            this.regeneratePaletteButton.Name = "regeneratePaletteButton";
            this.regeneratePaletteButton.Size = new System.Drawing.Size(75, 23);
            this.regeneratePaletteButton.TabIndex = 0;
            this.regeneratePaletteButton.Text = "Pal Regen";
            this.regeneratePaletteButton.UseVisualStyleBackColor = true;
            this.regeneratePaletteButton.Click += new System.EventHandler(this.regeneratePaletteButton_Click);
            // 
            // timer2
            // 
            this.timer2.Enabled = true;
            this.timer2.Tick += new System.EventHandler(this.timer2_Tick);
            // 
            // visualiseCullingCheckBox
            // 
            this.visualiseCullingCheckBox.AutoSize = true;
            this.visualiseCullingCheckBox.Location = new System.Drawing.Point(532, 10);
            this.visualiseCullingCheckBox.Name = "visualiseCullingCheckBox";
            this.visualiseCullingCheckBox.Size = new System.Drawing.Size(100, 17);
            this.visualiseCullingCheckBox.TabIndex = 7;
            this.visualiseCullingCheckBox.Text = "Visualise culling";
            this.visualiseCullingCheckBox.UseVisualStyleBackColor = true;
            this.visualiseCullingCheckBox.CheckedChanged += new System.EventHandler(this.visualiseCullingCheckBox_CheckedChanged);
            // 
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1042, 669);
            this.Controls.Add(this.splitContainer2);
            this.KeyPreview = true;
            this.Name = "Form1";
            this.Text = "SuperRT testbed";
            this.Activated += new System.EventHandler(this.Form1_Activated);
            this.Load += new System.EventHandler(this.Form1_Load);
            this.KeyDown += new System.Windows.Forms.KeyEventHandler(this.Form1_KeyDown);
            this.KeyUp += new System.Windows.Forms.KeyEventHandler(this.Form1_KeyUp);
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).EndInit();
            this.splitContainer1.Panel1.ResumeLayout(false);
            this.splitContainer1.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.splitContainer1)).EndInit();
            this.splitContainer1.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).EndInit();
            this.splitContainer2.Panel1.ResumeLayout(false);
            this.splitContainer2.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.splitContainer2)).EndInit();
            this.splitContainer2.ResumeLayout(false);
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.PictureBox pictureBox1;
        private System.Windows.Forms.SplitContainer splitContainer1;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Timer timer1;
        private System.Windows.Forms.SplitContainer splitContainer2;
        private System.Windows.Forms.RichTextBox pixelTraceBox;
        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.Button regeneratePaletteButton;
        private System.Windows.Forms.CheckBox palettizedDisplayCheckbox;
        private System.Windows.Forms.CheckBox rgb555DisplayCheckBox;
        private System.Windows.Forms.CheckBox ditherCheckbox;
        private System.Windows.Forms.CheckBox showBranchPredictionHitRateCheckbox;
        private System.Windows.Forms.Timer timer2;
        private System.Windows.Forms.Button writeData;
        private System.Windows.Forms.CheckBox animateCheckBox;
        private System.Windows.Forms.CheckBox visualiseCullingCheckBox;
    }
}

