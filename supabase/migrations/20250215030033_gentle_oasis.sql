-- Fix the log_admin_action function to properly cast action types
CREATE OR REPLACE FUNCTION log_admin_action()
RETURNS TRIGGER AS $$
DECLARE
  admin_user_id uuid;
  changes jsonb;
  action_type audit_action_type;
BEGIN
  -- Get admin user id
  SELECT id INTO admin_user_id
  FROM admin_users
  WHERE profile_id = auth.uid();

  -- Prepare changes JSON
  IF TG_OP = 'DELETE' THEN
    changes = jsonb_build_object('old_data', row_to_json(OLD));
  ELSIF TG_OP = 'UPDATE' THEN
    changes = jsonb_build_object(
      'old_data', row_to_json(OLD),
      'new_data', row_to_json(NEW)
    );
  ELSE
    changes = jsonb_build_object('new_data', row_to_json(NEW));
  END IF;

  -- Determine action type with proper casting
  action_type := CASE
    WHEN TG_OP = 'INSERT' THEN 'create'::audit_action_type
    WHEN TG_OP = 'UPDATE' THEN 'update'::audit_action_type
    WHEN TG_OP = 'DELETE' THEN 'delete'::audit_action_type
  END;

  -- Insert audit log
  INSERT INTO admin_audit_logs (
    admin_id,
    action,
    table_name,
    record_id,
    changes,
    ip_address,
    user_agent
  )
  VALUES (
    admin_user_id,
    action_type,
    TG_TABLE_NAME,
    CASE
      WHEN TG_OP = 'DELETE' THEN OLD.id
      ELSE NEW.id
    END,
    changes,
    inet_client_addr(),
    current_setting('request.headers')::json->>'user-agent'
  );

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;