function Show-ChangelogDialog {
    try {
        Write-Log "Opening changelog dialog..."

        $reader = (New-Object System.Xml.XmlNodeReader $changelogModalXaml)
        try {
            $changelogWindow = [Windows.Markup.XamlReader]::Load($reader)

            if ($null -eq $changelogWindow) {
                throw "Failed to create changelog window. XamlReader returned null."
            }
        }
        catch {
            Write-Log "Error loading changelog window: $_"
            [System.Windows.MessageBox]::Show(
                "Failed to create the changelog dialog. Error: $_",
                "Dialog Creation Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        # Get controls
        $closeButton = $changelogWindow.FindName('CloseChangelogButton')
        $contentBlock = $changelogWindow.FindName('ChangelogContent')

        # Add close button handler
        $closeButton.Add_Click({
                $changelogWindow.Close()
            })

        # Helper function to parse markdown formatting in text
        function Parse-MarkdownText {
            param($text, $paragraph)

            # Pattern to match bold (**text**), italic (*text*), and code (`text`) in any combination
            $pattern = '(\*\*[^\*]+\*\*|\*[^\*]+\*|`[^`]+`|[^*`]+)'

            $matches = [regex]::Matches($text, $pattern)

            foreach ($match in $matches) {
                $value = $match.Value

                if ($value -match '^\*\*(.+)\*\*$') {
                    # Bold text
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontWeight = 'Bold'
                    $paragraph.Inlines.Add($run)
                }
                elseif ($value -match '^\*([^\*]+)\*$') {
                    # Italic text
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontStyle = 'Italic'
                    $paragraph.Inlines.Add($run)
                }
                elseif ($value -match '^`([^`]+)`$') {
                    # Inline code
                    $run = New-Object System.Windows.Documents.Run($matches[1])
                    $run.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
                    $run.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(240, 240, 240))
                    $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(212, 0, 0))
                    $paragraph.Inlines.Add($run)
                }
                else {
                    # Regular text
                    if ($value.Trim()) {
                        $run = New-Object System.Windows.Documents.Run($value)
                        $paragraph.Inlines.Add($run)
                    }
                }
            }
        }

        # Fetch and display changelog content
        try {
            $markdownContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/ugurkocde/DeviceOffboardingManager/refs/heads/main/Changelog.md" -Method Get

            # Create new FlowDocument
            $flowDoc = New-Object System.Windows.Documents.FlowDocument
            $flowDoc.PageWidth = 700 # Set a fixed width for proper text flow

            # Process markdown content line by line
            $markdownContent -split "`n" | ForEach-Object {
                $line = $_.TrimEnd()

                if ($line) {
                    $paragraph = New-Object System.Windows.Documents.Paragraph

                    # Headers
                    if ($line -match '^(#{1,6})\s+(.+)$') {
                        $headerLevel = $matches[1].Length
                        $headerText = $matches[2]
                        $run = New-Object System.Windows.Documents.Run($headerText)
                        $run.FontSize = (24 - ($headerLevel * 2))
                        $run.FontWeight = 'Bold'
                        if ($headerLevel -eq 2) {
                            # Main version headers
                            $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0, 120, 212))
                        }
                        $paragraph.Inlines.Add($run)
                        $paragraph.Margin = New-Object System.Windows.Thickness(0, 10, 0, 5)
                    }
                    # List items
                    elseif ($line -match '^(\s*)-\s+(.+)$') {
                        $indent = $matches[1].Length
                        $listText = $matches[2]

                        # Calculate indentation level (2 spaces = 1 level)
                        $indentLevel = [Math]::Floor($indent / 2)
                        $leftMargin = 20 + ($indentLevel * 20)

                        # Add bullet
                        $bullet = New-Object System.Windows.Documents.Run('• ')
                        $bullet.FontWeight = 'Bold'
                        $paragraph.Inlines.Add($bullet)

                        # Parse the list item text for formatting
                        Parse-MarkdownText -text $listText -paragraph $paragraph

                        $paragraph.Margin = New-Object System.Windows.Thickness($leftMargin, 0, 0, 5)
                    }
                    # Regular paragraph that might contain formatting
                    else {
                        Parse-MarkdownText -text $line -paragraph $paragraph
                        $paragraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
                    }

                    $flowDoc.Blocks.Add($paragraph)
                }
                else {
                    # Empty line - add spacing
                    $paragraph = New-Object System.Windows.Documents.Paragraph
                    $paragraph.Margin = New-Object System.Windows.Thickness(0, 5, 0, 5)
                    $flowDoc.Blocks.Add($paragraph)
                }
            }

            # Set the FlowDocument to the RichTextBox
            $contentBlock.Document = $flowDoc
            Write-Log "Successfully loaded changelog content"
        }
        catch {
            Write-Log "Error fetching changelog: $_"

            # Create error message in FlowDocument
            $flowDoc = New-Object System.Windows.Documents.FlowDocument
            $paragraph = New-Object System.Windows.Documents.Paragraph
            $run = New-Object System.Windows.Documents.Run("Error loading changelog. Please check your internet connection and try again.")
            $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(220, 38, 38))
            $paragraph.Inlines.Add($run)
            $flowDoc.Blocks.Add($paragraph)
            $contentBlock.Document = $flowDoc
        }

        # Show dialog
        try {
            if ($null -eq $changelogWindow) {
                throw "Changelog window is null. Cannot show dialog."
            }
            $changelogWindow.ShowDialog()
        }
        catch {
            Write-Log "Error showing changelog dialog: $_"
            [System.Windows.MessageBox]::Show(
                "Failed to show the changelog dialog. Error: $_",
                "Dialog Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
    catch {
        Write-Log "Error showing changelog dialog: $_"
        [System.Windows.MessageBox]::Show(
            "Error showing changelog dialog: $_",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
